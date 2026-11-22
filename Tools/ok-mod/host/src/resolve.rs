//! Which discovered mods load, and in what order (§6.1): duplicates, target, api version, player
//! disable list, incompatibilities, dependencies (cascading), load order and cycles.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::path::PathBuf;

use semver::Version;

use crate::manifest::{api_compatible, parse_api, Manifest};

pub struct Candidate {
    pub dir: PathBuf,
    pub manifest: Result<Manifest, String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Verdict {
    /// Position in the load order.
    Load(usize),
    /// Not an error: not for this mode, or turned off by the player.
    Skip(String),
    /// Will not load, with the reason shown to the player.
    Reject(String),
}

pub struct Resolved {
    pub dir: PathBuf,
    /// Mod id, or the folder name when `mod.toml` could not be read.
    pub id: String,
    pub manifest: Option<Manifest>,
    pub verdict: Verdict,
}

/// `targets`: the modes this process runs (a mod loads if it targets any of them).
pub fn resolve(candidates: Vec<Candidate>, targets: &[String], disabled: &HashSet<String>, host_api: (u64, u64)) -> Vec<Resolved> {
    let mut out: Vec<Resolved> = candidates
        .into_iter()
        .map(|c| {
            let folder = c.dir.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            match c.manifest {
                Ok(m) => Resolved { dir: c.dir, id: m.id.clone(), manifest: Some(m), verdict: Verdict::Load(0) },
                Err(e) => Resolved { dir: c.dir, id: folder, manifest: None, verdict: Verdict::Reject(e) },
            }
        })
        .collect();

    // Same id twice: keep the newest version (HF_Patch RemoveSideloaderDuplicates).
    let mut newest: BTreeMap<String, (Version, usize)> = BTreeMap::new();
    for (i, r) in out.iter().enumerate() {
        if let Some(m) = &r.manifest {
            match newest.get(&m.id) {
                Some((v, _)) if *v >= m.version => {}
                _ => {
                    newest.insert(m.id.clone(), (m.version.clone(), i));
                }
            }
        }
    }
    for (i, r) in out.iter_mut().enumerate() {
        if let Some(m) = &r.manifest {
            let (v, keep) = &newest[&m.id];
            if *keep != i {
                r.verdict = Verdict::Reject(format!("duplicate: {} {} is also installed, this copy ({}) is ignored", m.id, v, m.version));
            }
        }
    }

    for r in out.iter_mut() {
        let (Some(m), Verdict::Load(_)) = (&r.manifest, &r.verdict) else { continue };
        if !m.targets.iter().any(|t| targets.contains(t)) {
            r.verdict = Verdict::Skip(format!("not for mode {} (targets: {})", targets.join("/"), m.targets.join(", ")));
        } else if !api_compatible(parse_api(&m.api).unwrap_or((u64::MAX, 0)), host_api) {
            r.verdict = Verdict::Reject(format!("needs ok-mod-api {}, this host has {}.{}", m.api, host_api.0, host_api.1));
        } else if disabled.contains(&m.id) {
            r.verdict = Verdict::Skip("disabled by the player".into());
        }
    }

    // Incompatibilities: the mod that declares one does not load (BepInIncompatibility).
    let present = |out: &[Resolved]| -> BTreeMap<String, Version> {
        out.iter()
            .filter(|r| matches!(r.verdict, Verdict::Load(_)))
            .filter_map(|r| r.manifest.as_ref().map(|m| (m.id.clone(), m.version.clone())))
            .collect()
    };
    let loaded = present(&out);
    for r in out.iter_mut() {
        let (Some(m), Verdict::Load(_)) = (&r.manifest, &r.verdict) else { continue };
        if let Some((other, v)) = m.incompatible.iter().find_map(|(id, req)| loaded.get(id).filter(|v| req.matches(v)).map(|v| (id, v))) {
            r.verdict = Verdict::Reject(format!("incompatible with {other} {v}"));
        }
    }

    // Hard dependencies, until nothing changes (a rejected dependency rejects its dependents).
    loop {
        let loaded = present(&out);
        let mut changed = false;
        for r in out.iter_mut() {
            let (Some(m), Verdict::Load(_)) = (&r.manifest, &r.verdict) else { continue };
            for (dep, req) in &m.dependencies {
                let reason = match loaded.get(dep) {
                    None => Some(format!("needs {dep} {req}, which is not installed or not loaded")),
                    Some(v) if !req.matches(v) => Some(format!("needs {dep} {req}, installed is {v}")),
                    _ => None,
                };
                if let Some(reason) = reason {
                    r.verdict = Verdict::Reject(reason);
                    changed = true;
                    break;
                }
            }
        }
        if !changed {
            break;
        }
    }

    // Order: dependencies, present optional dependencies and load_order.after go first;
    // load_order.before goes the other way. Ties by id so the order is stable.
    loop {
        let loaded = present(&out);
        let ids: Vec<String> = loaded.keys().cloned().collect();
        let mut before: BTreeMap<String, BTreeSet<String>> = ids.iter().map(|id| (id.clone(), BTreeSet::new())).collect();
        for r in &out {
            let (Some(m), Verdict::Load(_)) = (&r.manifest, &r.verdict) else { continue };
            let firsts = m.dependencies.keys().chain(m.optional_dependencies.keys()).chain(m.load_order.after.iter());
            for f in firsts {
                if loaded.contains_key(f) {
                    before.get_mut(&m.id).unwrap().insert(f.clone());
                }
            }
            for later in &m.load_order.before {
                if let Some(set) = before.get_mut(later) {
                    set.insert(m.id.clone());
                }
            }
        }
        let mut order: Vec<String> = Vec::new();
        let mut done: HashSet<String> = HashSet::new();
        loop {
            let next = before.iter().find(|(id, deps)| !done.contains(*id) && deps.iter().all(|d| done.contains(d))).map(|(id, _)| id.clone());
            match next {
                Some(id) => {
                    done.insert(id.clone());
                    order.push(id);
                }
                None => break,
            }
        }
        if order.len() == ids.len() {
            for r in out.iter_mut() {
                if let (Some(m), Verdict::Load(_)) = (&r.manifest, &r.verdict) {
                    r.verdict = Verdict::Load(order.iter().position(|id| id == &m.id).unwrap());
                }
            }
            break;
        }
        // Whatever is left is in or behind a cycle: reject the ones in the cycle and redo the rest.
        let stuck: BTreeSet<String> = ids.iter().filter(|id| !done.contains(*id)).cloned().collect();
        let in_cycle: Vec<String> = stuck.iter().filter(|id| reaches_itself(id, &before, &stuck)).cloned().collect();
        let names = in_cycle.join(", ");
        for r in out.iter_mut() {
            if let Some(m) = &r.manifest {
                if in_cycle.contains(&m.id) {
                    r.verdict = Verdict::Reject(format!("load order cycle between {names}"));
                }
            }
        }
        // Dependents of rejected cycle members fail their dependency check next round.
        loop {
            let loaded = present(&out);
            let mut changed = false;
            for r in out.iter_mut() {
                let (Some(m), Verdict::Load(_)) = (&r.manifest, &r.verdict) else { continue };
                if let Some(dep) = m.dependencies.keys().find(|d| !loaded.contains_key(*d)) {
                    r.verdict = Verdict::Reject(format!("needs {dep}, which is not loaded"));
                    changed = true;
                }
            }
            if !changed {
                break;
            }
        }
    }
    out
}

fn reaches_itself(start: &str, before: &BTreeMap<String, BTreeSet<String>>, within: &BTreeSet<String>) -> bool {
    let mut stack: Vec<&str> = before[start].iter().map(|s| s.as_str()).filter(|s| within.contains(*s)).collect();
    let mut seen: HashSet<&str> = HashSet::new();
    while let Some(id) = stack.pop() {
        if id == start {
            return true;
        }
        if seen.insert(id) {
            stack.extend(before[id].iter().map(|s| s.as_str()).filter(|s| within.contains(*s)));
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cand(toml_body: &str) -> Candidate {
        let text = format!("name = \"x\"\napi = \"0.1\"\ndll = \"x.dll\"\ntargets = [\"reader\"]\n{toml_body}");
        Candidate { dir: PathBuf::from("Mods/x"), manifest: Manifest::parse(&text) }
    }

    fn verdicts(out: &[Resolved]) -> BTreeMap<String, Verdict> {
        out.iter().map(|r| (format!("{}@{}", r.id, r.manifest.as_ref().map(|m| m.version.to_string()).unwrap_or_default()), r.verdict.clone())).collect()
    }

    #[test]
    fn order_and_dependencies() {
        let out = resolve(
            vec![
                cand("id = \"a.b\"\nversion = \"1.0.0\"\n[dependencies]\n\"a.core\" = \"^1\""),
                cand("id = \"a.core\"\nversion = \"1.2.0\""),
                cand("id = \"a.c\"\nversion = \"1.0.0\"\n[dependencies]\n\"a.missing\" = \"*\""),
                cand("id = \"a.d\"\nversion = \"1.0.0\"\n[dependencies]\n\"a.c\" = \"*\""),
                cand("id = \"a.e\"\nversion = \"1.0.0\"\n[load_order]\nbefore = [\"a.core\"]"),
            ],
            &["reader".to_string()],
            &HashSet::new(),
            (0, 1),
        );
        let v = verdicts(&out);
        assert_eq!(v["a.e@1.0.0"], Verdict::Load(0));
        assert_eq!(v["a.core@1.2.0"], Verdict::Load(1));
        assert_eq!(v["a.b@1.0.0"], Verdict::Load(2));
        assert!(matches!(&v["a.c@1.0.0"], Verdict::Reject(r) if r.contains("a.missing")));
        assert!(matches!(&v["a.d@1.0.0"], Verdict::Reject(r) if r.contains("a.c")));
    }

    #[test]
    fn duplicates_versions_targets_api_cycles() {
        let out = resolve(
            vec![
                cand("id = \"a.dup\"\nversion = \"1.0.0\""),
                cand("id = \"a.dup\"\nversion = \"1.1.0\""),
                cand("id = \"a.old\"\nversion = \"1.0.0\"\n[dependencies]\n\"a.dup\" = \"^2\""),
                Candidate {
                    dir: PathBuf::from("Mods/s"),
                    manifest: Manifest::parse("id = \"a.studio\"\nname = \"s\"\nversion = \"1.0.0\"\napi = \"0.1\"\ndll = \"s.dll\"\ntargets = [\"studio\"]"),
                },
                Candidate { dir: PathBuf::from("Mods/broken"), manifest: Manifest::parse("id = \"a.broken\"\nunknown_key = 1") },
                Candidate {
                    dir: PathBuf::from("Mods/n"),
                    manifest: Manifest::parse("id = \"a.newapi\"\nname = \"n\"\nversion = \"1.0.0\"\napi = \"0.2\"\ndll = \"n.dll\"\ntargets = [\"reader\"]"),
                },
                cand("id = \"a.x\"\nversion = \"1.0.0\"\n[load_order]\nafter = [\"a.y\"]"),
                cand("id = \"a.y\"\nversion = \"1.0.0\"\n[load_order]\nafter = [\"a.x\"]"),
                cand("id = \"a.z\"\nversion = \"1.0.0\"\n[dependencies]\n\"a.x\" = \"*\""),
                cand("id = \"a.off\"\nversion = \"1.0.0\""),
                cand("id = \"a.hater\"\nversion = \"1.0.0\"\n[incompatible]\n\"a.off2\" = \"*\""),
                cand("id = \"a.off2\"\nversion = \"1.0.0\""),
            ],
            &["reader".to_string()],
            &["a.off".to_string()].into_iter().collect(),
            (0, 1),
        );
        let v = verdicts(&out);
        assert!(matches!(&v["a.dup@1.0.0"], Verdict::Reject(r) if r.contains("duplicate")));
        assert!(matches!(&v["a.dup@1.1.0"], Verdict::Load(_)));
        assert!(matches!(&v["a.old@1.0.0"], Verdict::Reject(r) if r.contains("installed is 1.1.0")));
        assert!(matches!(&v["a.studio@1.0.0"], Verdict::Skip(r) if r.contains("not for mode")));
        assert!(matches!(&v["broken@"], Verdict::Reject(r) if r.contains("mod.toml")));
        assert!(matches!(&v["a.newapi@1.0.0"], Verdict::Reject(r) if r.contains("0.2")));
        assert!(matches!(&v["a.x@1.0.0"], Verdict::Reject(r) if r.contains("cycle")));
        assert!(matches!(&v["a.y@1.0.0"], Verdict::Reject(r) if r.contains("cycle")));
        assert!(matches!(&v["a.z@1.0.0"], Verdict::Reject(_)));
        assert!(matches!(&v["a.off@1.0.0"], Verdict::Skip(r) if r.contains("player")));
        assert!(matches!(&v["a.hater@1.0.0"], Verdict::Reject(r) if r.contains("incompatible")));
        assert!(matches!(&v["a.off2@1.0.0"], Verdict::Load(_)));
    }
}
