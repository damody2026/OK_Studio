//! Config entries the host keeps for each mod (`UserData/config/mods/<id>.toml`; mods never write
//! files themselves, §5).

use std::collections::BTreeMap;
use std::path::PathBuf;

use ok_mod_api::{ConfigDecl, ConfigValue};

#[derive(Debug, Clone)]
pub struct Entry {
    pub key: String,
    pub default: ConfigValue,
    pub min: Option<f64>,
    pub max: Option<f64>,
    pub description_id: String,
}

impl Entry {
    pub fn from_decl(d: &ConfigDecl) -> Option<Entry> {
        Some(Entry {
            key: d.key.to_string(),
            default: d.default.as_enum().ok()?.clone(),
            min: d.min.into_option(),
            max: d.max.into_option(),
            description_id: d.description_id.to_string(),
        })
    }

    /// Checks `value` against the entry's type and range; an `Int` is accepted for a `Float`.
    pub fn check(&self, value: ConfigValue) -> Result<ConfigValue, String> {
        let value = match (&self.default, value) {
            (ConfigValue::Bool(_), v @ ConfigValue::Bool(_)) => v,
            (ConfigValue::Int(_), v @ ConfigValue::Int(_)) => v,
            (ConfigValue::Float(_), ConfigValue::Int(i)) => ConfigValue::Float(i as f64),
            (ConfigValue::Float(_), v @ ConfigValue::Float(_)) => v,
            (ConfigValue::Text(_), v @ ConfigValue::Text(_)) => v,
            (ConfigValue::Hotkey(_), ConfigValue::Text(s) | ConfigValue::Hotkey(s)) => ConfigValue::Hotkey(s),
            (want, got) => return Err(format!("{}: expected {}, got {}", self.key, type_name(want), type_name(&got))),
        };
        let n = match &value {
            ConfigValue::Int(i) => Some(*i as f64),
            ConfigValue::Float(f) => Some(*f),
            _ => None,
        };
        if let Some(n) = n {
            if !n.is_finite() || self.min.is_some_and(|m| n < m) || self.max.is_some_and(|m| n > m) {
                return Err(format!("{}: {n} is outside {}..={}", self.key, fmt_bound(self.min), fmt_bound(self.max)));
            }
        }
        Ok(value)
    }
}

fn fmt_bound(b: Option<f64>) -> String {
    b.map(|b| b.to_string()).unwrap_or_default()
}

pub fn type_name(v: &ConfigValue) -> &'static str {
    match v {
        ConfigValue::Bool(_) => "bool",
        ConfigValue::Int(_) => "int",
        ConfigValue::Float(_) => "float",
        ConfigValue::Text(_) => "text",
        ConfigValue::Hotkey(_) => "hotkey",
        _ => "unknown",
    }
}

#[derive(Default)]
pub struct Store {
    pub entries: Vec<Entry>,
    pub values: BTreeMap<String, ConfigValue>,
    pub path: Option<PathBuf>,
}

impl Store {
    pub fn entry(&self, key: &str) -> Option<&Entry> {
        self.entries.iter().find(|e| e.key == key)
    }

    pub fn get(&self, key: &str) -> Option<ConfigValue> {
        let e = self.entry(key)?;
        Some(self.values.get(key).cloned().unwrap_or_else(|| e.default.clone()))
    }

    /// Declares the entries and reads saved values; values that no longer fit are dropped with a
    /// warning (returned).
    pub fn declare(&mut self, entries: Vec<Entry>, path: Option<PathBuf>) -> Vec<String> {
        self.entries = entries;
        self.path = path;
        let mut warnings = Vec::new();
        let Some(path) = &self.path else { return warnings };
        let Ok(text) = std::fs::read_to_string(path) else { return warnings };
        let table: toml::Table = match toml::from_str(&text) {
            Ok(t) => t,
            Err(e) => {
                warnings.push(format!("{}: {e}; using defaults", path.display()));
                return warnings;
            }
        };
        for (key, raw) in table {
            let Some(entry) = self.entry(&key).cloned() else { continue };
            match from_toml(&raw).ok_or_else(|| format!("{key}: unsupported value {raw}")).and_then(|v| entry.check(v)) {
                Ok(v) => {
                    self.values.insert(key, v);
                }
                Err(e) => warnings.push(format!("{}: {e}; using the default", path.display())),
            }
        }
        warnings
    }

    pub fn set(&mut self, key: &str, value: ConfigValue) -> Result<(), String> {
        let entry = self.entry(key).ok_or_else(|| format!("no config entry {key}"))?;
        let value = entry.check(value)?;
        self.values.insert(key.to_string(), value);
        self.save()
    }

    fn save(&self) -> Result<(), String> {
        let Some(path) = &self.path else { return Ok(()) };
        let mut table = toml::Table::new();
        for (k, v) in &self.values {
            table.insert(k.clone(), to_toml(v));
        }
        let text = toml::to_string(&table).map_err(|e| e.to_string())?;
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        }
        let tmp = path.with_extension("toml.tmp");
        std::fs::write(&tmp, text).map_err(|e| format!("{}: {e}", tmp.display()))?;
        std::fs::rename(&tmp, path).map_err(|e| format!("{}: {e}", path.display()))
    }
}

pub fn to_toml(v: &ConfigValue) -> toml::Value {
    match v {
        ConfigValue::Bool(b) => toml::Value::Boolean(*b),
        ConfigValue::Int(i) => toml::Value::Integer(*i),
        ConfigValue::Float(f) => toml::Value::Float(*f),
        ConfigValue::Text(s) | ConfigValue::Hotkey(s) => toml::Value::String(s.to_string()),
        _ => toml::Value::String(String::new()),
    }
}

pub fn from_toml(v: &toml::Value) -> Option<ConfigValue> {
    Some(match v {
        toml::Value::Boolean(b) => ConfigValue::Bool(*b),
        toml::Value::Integer(i) => ConfigValue::Int(*i),
        toml::Value::Float(f) => ConfigValue::Float(*f),
        toml::Value::String(s) => ConfigValue::Text(s.as_str().into()),
        _ => return None,
    })
}

pub fn to_json(v: &ConfigValue) -> serde_json::Value {
    match v {
        ConfigValue::Bool(b) => (*b).into(),
        ConfigValue::Int(i) => (*i).into(),
        ConfigValue::Float(f) => (*f).into(),
        ConfigValue::Text(s) | ConfigValue::Hotkey(s) => s.as_str().into(),
        _ => serde_json::Value::Null,
    }
}

pub fn from_json(v: &serde_json::Value) -> Option<ConfigValue> {
    Some(match v {
        serde_json::Value::Bool(b) => ConfigValue::Bool(*b),
        serde_json::Value::Number(n) => match n.as_i64() {
            Some(i) => ConfigValue::Int(i),
            None => ConfigValue::Float(n.as_f64()?),
        },
        serde_json::Value::String(s) => ConfigValue::Text(s.as_str().into()),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn int_entry() -> Entry {
        Entry { key: "n".into(), default: ConfigValue::Int(1), min: Some(0.0), max: Some(10.0), description_id: String::new() }
    }

    #[test]
    fn checks() {
        let e = int_entry();
        assert!(e.check(ConfigValue::Int(5)).is_ok());
        assert!(e.check(ConfigValue::Int(11)).is_err());
        assert!(e.check(ConfigValue::Bool(true)).is_err());
        let f = Entry { default: ConfigValue::Float(0.5), ..int_entry() };
        assert_eq!(f.check(ConfigValue::Int(2)).unwrap(), ConfigValue::Float(2.0));
    }

    #[test]
    fn save_and_reload() {
        let dir = std::env::temp_dir().join(format!("ok-mod-config-test-{}", std::process::id()));
        let path = dir.join("a.b.toml");
        let _ = std::fs::remove_dir_all(&dir);
        let mut s = Store::default();
        s.declare(vec![int_entry()], Some(path.clone()));
        assert_eq!(s.get("n"), Some(ConfigValue::Int(1)));
        s.set("n", ConfigValue::Int(7)).unwrap();
        let mut again = Store::default();
        assert!(again.declare(vec![int_entry()], Some(path.clone())).is_empty());
        assert_eq!(again.get("n"), Some(ConfigValue::Int(7)));
        std::fs::write(&path, "n = 99\n").unwrap();
        let mut bad = Store::default();
        assert_eq!(bad.declare(vec![int_entry()], Some(path)).len(), 1);
        assert_eq!(bad.get("n"), Some(ConfigValue::Int(1)));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
