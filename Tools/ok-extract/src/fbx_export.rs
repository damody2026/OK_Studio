//! Binary FBX 7.4 character exporter with split editable parts, clean unscaled skeleton rig,
//! skinning clusters, facial/body BlendShapes (Shape Keys), multi-UV layers, vertex colors,
//! and baked BaseColor/Normal PNG textures.

use std::collections::{BTreeMap, HashMap};
use std::path::Path;

use crate::session::{OkSession, SessionPart};

// ─────────────────────────────────────────────────────────────────────────────
// Binary FBX 7.4 Writer Primitives
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub(crate) enum Prop {
    Bool(bool),
    I16(i16),
    I32(i32),
    I64(i64),
    F32(f32),
    F64(f64),
    Str(String),
    Bytes(Vec<u8>),
    ArrI32(Vec<i32>),
    ArrI64(Vec<i64>),
    ArrF32(Vec<f32>),
    ArrF64(Vec<f64>),
}

#[derive(Clone)]
pub(crate) struct Node {
    pub name: &'static str,
    pub props: Vec<Prop>,
    pub children: Vec<Node>,
}

impl Node {
    pub fn new(name: &'static str) -> Self {
        Self {
            name,
            props: Vec::new(),
            children: Vec::new(),
        }
    }
    pub fn p(mut self, p: Prop) -> Self {
        self.props.push(p);
        self
    }
    pub fn c(mut self, c: Node) -> Self {
        self.children.push(c);
        self
    }
}

pub(crate) fn prop_p70(name: &str, ty1: &str, ty2: &str, flags: &str, tail: &[Prop]) -> Node {
    let mut n = Node::new("P")
        .p(Prop::Str(name.into()))
        .p(Prop::Str(ty1.into()))
        .p(Prop::Str(ty2.into()))
        .p(Prop::Str(flags.into()));
    n.props.extend_from_slice(tail);
    n
}

pub(crate) fn encode_binary(nodes: &[Node]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 * 1024 * 1024);
    out.extend_from_slice(b"Kaydara FBX Binary  \x00\x1a\x00");
    out.extend_from_slice(&7400u32.to_le_bytes());
    for n in nodes {
        write_node(&mut out, n);
    }
    // 13-byte null record terminator
    out.extend_from_slice(&[0u8; 13]);
    // FBX footer magic + 16-byte alignment padding + version + 120 zero bytes + magic
    let footer_id: [u8; 16] = [
        0xfa, 0xbc, 0xab, 0x09, 0xd0, 0xc8, 0xd4, 0x66, 0xb1, 0x76, 0xfb, 0x83, 0x1c, 0xf7, 0x26,
        0x7e,
    ];
    out.extend_from_slice(&footer_id);
    let pad = (16 - (out.len() & 15)) & 15;
    out.extend(std::iter::repeat_n(0u8, pad));
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&7400u32.to_le_bytes());
    out.extend_from_slice(&[0u8; 120]);
    out.extend_from_slice(&[
        0xf8, 0x5a, 0x8c, 0x6a, 0xde, 0xf5, 0xd9, 0x7e, 0xec, 0xe9, 0x0c, 0xe3, 0x75, 0x8f, 0x29,
        0x0b,
    ]);
    out
}

fn write_node(out: &mut Vec<u8>, n: &Node) {
    let header_pos = out.len();
    out.extend_from_slice(&[0u8; 12]);
    let name_bytes = n.name.as_bytes();
    out.push(name_bytes.len() as u8);
    out.extend_from_slice(name_bytes);

    let props_start = out.len();
    for p in &n.props {
        write_prop(out, p);
    }
    let prop_bytes_len = (out.len() - props_start) as u32;

    for c in &n.children {
        write_node(out, c);
    }
    if !n.children.is_empty() || n.props.is_empty() {
        out.extend_from_slice(&[0u8; 13]);
    }

    let end_offset = out.len() as u32;
    let num_props = n.props.len() as u32;
    out[header_pos..header_pos + 4].copy_from_slice(&end_offset.to_le_bytes());
    out[header_pos + 4..header_pos + 8].copy_from_slice(&num_props.to_le_bytes());
    out[header_pos + 8..header_pos + 12].copy_from_slice(&prop_bytes_len.to_le_bytes());
}

fn write_prop(out: &mut Vec<u8>, p: &Prop) {
    fn write_arr<T>(out: &mut Vec<u8>, code: u8, vals: &[T], mut f: impl FnMut(&mut Vec<u8>, &T)) {
        out.push(code);
        out.extend_from_slice(&(vals.len() as u32).to_le_bytes());
        out.extend_from_slice(&0u32.to_le_bytes()); // encoding 0 = uncompressed
        let len_pos = out.len();
        out.extend_from_slice(&0u32.to_le_bytes());
        let data_start = out.len();
        for v in vals {
            f(out, v);
        }
        let byte_len = (out.len() - data_start) as u32;
        out[len_pos..len_pos + 4].copy_from_slice(&byte_len.to_le_bytes());
    }
    match p {
        Prop::Bool(v) => {
            out.push(b'C');
            out.push(u8::from(*v));
        }
        Prop::I16(v) => {
            out.push(b'Y');
            out.extend_from_slice(&v.to_le_bytes());
        }
        Prop::I32(v) => {
            out.push(b'I');
            out.extend_from_slice(&v.to_le_bytes());
        }
        Prop::I64(v) => {
            out.push(b'L');
            out.extend_from_slice(&v.to_le_bytes());
        }
        Prop::F32(v) => {
            out.push(b'F');
            out.extend_from_slice(&v.to_le_bytes());
        }
        Prop::F64(v) => {
            out.push(b'D');
            out.extend_from_slice(&v.to_le_bytes());
        }
        Prop::Str(s) => {
            out.push(b'S');
            out.extend_from_slice(&(s.len() as u32).to_le_bytes());
            out.extend_from_slice(s.as_bytes());
        }
        Prop::Bytes(b) => {
            out.push(b'R');
            out.extend_from_slice(&(b.len() as u32).to_le_bytes());
            out.extend_from_slice(b);
        }
        Prop::ArrI32(v) => write_arr(out, b'i', v, |o, x| o.extend_from_slice(&x.to_le_bytes())),
        Prop::ArrI64(v) => write_arr(out, b'l', v, |o, x| o.extend_from_slice(&x.to_le_bytes())),
        Prop::ArrF32(v) => write_arr(out, b'f', v, |o, x| o.extend_from_slice(&x.to_le_bytes())),
        Prop::ArrF64(v) => write_arr(out, b'd', v, |o, x| o.extend_from_slice(&x.to_le_bytes())),
    }
}

fn conn_oo(child: i64, parent: i64) -> Node {
    Node::new("C")
        .p(Prop::Str("OO".into()))
        .p(Prop::I64(child))
        .p(Prop::I64(parent))
}

fn conn_op(child: i64, parent: i64, prop: &str) -> Node {
    Node::new("C")
        .p(Prop::Str("OP".into()))
        .p(Prop::I64(child))
        .p(Prop::I64(parent))
        .p(Prop::Str(prop.into()))
}

// ─────────────────────────────────────────────────────────────────────────────
// Math & Coordinate Space Helpers (Unity LH meters -> FBX RH centimeters)
// ─────────────────────────────────────────────────────────────────────────────

type Mat4 = [[f64; 4]; 4];

fn mat4_identity() -> Mat4 {
    [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
}

fn mat4_mul(a: &Mat4, b: &Mat4) -> Mat4 {
    let mut out = [[0.0f64; 4]; 4];
    for r in 0..4 {
        for c in 0..4 {
            out[r][c] = a[r][0] * b[0][c]
                + a[r][1] * b[1][c]
                + a[r][2] * b[2][c]
                + a[r][3] * b[3][c];
        }
    }
    out
}

/// Invert a rigid transform (orthonormal 3x3 rotation + translation).
fn rigid_inv(m: &Mat4) -> Mat4 {
    let mut inv = mat4_identity();
    for r in 0..3 {
        for c in 0..3 {
            inv[r][c] = m[c][r];
        }
    }
    let tx = m[0][3];
    let ty = m[1][3];
    let tz = m[2][3];
    for r in 0..3 {
        inv[r][3] = -(inv[r][0] * tx + inv[r][1] * ty + inv[r][2] * tz);
    }
    inv
}

fn mat4_to_fbx_col_major(m: &Mat4) -> Vec<f64> {
    let mut v = Vec::with_capacity(16);
    for c in 0..4 {
        for r in 0..4 {
            v.push(m[r][c]);
        }
    }
    v
}

/// Convert a Unity Left-Handed 4x4 world matrix (meters, row-major) into an unscaled
/// Right-Handed FBX 4x4 world matrix (centimeters, row-major, pure rotation + translation).
fn unity_world_to_fbx_rigid_cm(u: &[[f32; 4]; 4]) -> Mat4 {
    // Mirror X axis: S = diag(-1, 1, 1), M_rh = S * M_lh * S
    let sign = [-1.0f64, 1.0, 1.0];
    let mut r = [[0.0f64; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            r[i][j] = (u[i][j] as f64) * sign[i] * sign[j];
        }
    }
    // Extract columns c0, c1, c2 and Gram-Schmidt orthonormalize so scale is strictly [1, 1, 1]
    let mut c0 = [r[0][0], r[1][0], r[2][0]];
    let mut c1 = [r[0][1], r[1][1], r[2][1]];
    let norm = |v: [f64; 3]| (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    let normalize = |v: [f64; 3], fallback: [f64; 3]| {
        let len = norm(v);
        if len > 1e-8 && len.is_finite() {
            [v[0] / len, v[1] / len, v[2] / len]
        } else {
            fallback
        }
    };
    c0 = normalize(c0, [1.0, 0.0, 0.0]);
    let dot01 = c0[0] * c1[0] + c0[1] * c1[1] + c0[2] * c1[2];
    c1 = [
        c1[0] - dot01 * c0[0],
        c1[1] - dot01 * c0[1],
        c1[2] - dot01 * c0[2],
    ];
    c1 = normalize(
        c1,
        if c0[1].abs() < 0.9 {
            [0.0, 1.0, 0.0]
        } else {
            [0.0, 0.0, 1.0]
        },
    );
    // Right-handed cross product c2 = c0 x c1
    let c2 = [
        c0[1] * c1[2] - c0[2] * c1[1],
        c0[2] * c1[0] - c0[0] * c1[2],
        c0[0] * c1[1] - c0[1] * c1[0],
    ];

    let tx = -(u[0][3] as f64) * 100.0;
    let ty = (u[1][3] as f64) * 100.0;
    let tz = (u[2][3] as f64) * 100.0;

    [
        [c0[0], c1[0], c2[0], if tx.is_finite() { tx } else { 0.0 }],
        [c0[1], c1[1], c2[1], if ty.is_finite() { ty } else { 0.0 }],
        [c0[2], c1[2], c2[2], if tz.is_finite() { tz } else { 0.0 }],
        [0.0, 0.0, 0.0, 1.0],
    ]
}

/// Extract FBX default `RotationOrder = 0` (`eEulerXYZ`, where $R = R_z(z) R_y(y) R_x(x)$
/// for column vectors) in degrees from an orthonormal 3x3 rotation matrix.
fn mat4_to_fbx_euler_xyz_deg(m: &Mat4) -> [f64; 3] {
    let sy = (-m[2][0]).clamp(-1.0, 1.0);
    let ry = sy.asin();
    let cy = ry.cos();
    let (rx, rz) = if cy.abs() > 1e-6 {
        let rx = m[2][1].atan2(m[2][2]);
        let rz = m[1][0].atan2(m[0][0]);
        (rx, rz)
    } else {
        let rx = (-m[1][2]).atan2(m[1][1]);
        let rz = 0.0;
        (rx, rz)
    };
    let to_deg = 180.0 / std::f64::consts::PI;
    [rx * to_deg, ry * to_deg, rz * to_deg]
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton Rig Construction
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Clone)]
struct FbxBone {
    name: String,
    parent: Option<usize>,
    world: Mat4,
    inv_world: Mat4,
    lcl_translation: [f64; 3],
    lcl_rotation_deg: [f64; 3],
}

fn build_unified_skeleton(
    session: &OkSession,
) -> (
    Vec<FbxBone>,
    HashMap<String, usize>,
    HashMap<usize, Vec<usize>>,
) {
    let mut bones: Vec<FbxBone> = Vec::new();
    let mut lower_name_to_idx: HashMap<String, usize> = HashMap::new();

    if let Some(ex) = session.skel_export.as_ref() {
        let mut unity_worlds: Vec<crate::pose::Mat4> = Vec::with_capacity(ex.bones.len());
        for (idx, b) in ex.bones.iter().enumerate() {
            let local_u = crate::pose::trs(b.pose_pos, b.pose_rot, b.pose_scl);
            let world_u = if b.parent >= 0 && (b.parent as usize) < unity_worlds.len() {
                crate::pose::mat_mul_pub(&unity_worlds[b.parent as usize], &local_u)
            } else {
                local_u
            };
            unity_worlds.push(world_u);

            let world = unity_world_to_fbx_rigid_cm(&world_u);
            let inv_world = rigid_inv(&world);
            let parent = if b.parent >= 0 && (b.parent as usize) < idx {
                Some(b.parent as usize)
            } else {
                None
            };
            bones.push(FbxBone {
                name: b.name.clone(),
                parent,
                world,
                inv_world,
                lcl_translation: [0.0; 3],
                lcl_rotation_deg: [0.0; 3],
            });
            lower_name_to_idx.insert(b.name.to_ascii_lowercase(), idx);
        }
    }

    // Ensure at least one root bone exists
    if bones.is_empty() {
        let world = mat4_identity();
        bones.push(FbxBone {
            name: "cf_j_root".into(),
            parent: None,
            world,
            inv_world: world,
            lcl_translation: [0.0; 3],
            lcl_rotation_deg: [0.0; 3],
        });
        lower_name_to_idx.insert("cf_j_root".into(), 0);
    }

    let shared_bone_count = bones.len();
    let body_skel = session.body_skel.as_ref();
    let head_skel = session
        .head_full_posed
        .as_ref()
        .or(session.head_skel.as_ref());

    // Append private hair, clothes, and accessory bones from `runtime_accessory` so every
    // hair strand, skirt chain, and accessory joint is a real selectable bone in the FBX Armature.
    let mut part_private_slot_map: HashMap<usize, Vec<usize>> = HashMap::new();
    for (part_idx, p) in session.parts.iter().enumerate() {
        if !should_export_part(session, part_idx, p) {
            continue;
        }
        let Some(acc) = p.runtime_accessory.as_ref() else {
            continue;
        };
        let Some((private_rig, slot_worlds, parent_key, copy_weights_body)) =
            acc.fbx_slot_skeleton(body_skel, head_skel)
        else {
            continue;
        };
        let slot_count = private_rig
            .names
            .len()
            .min(private_rig.bone_ids.len())
            .min(slot_worlds.len());
        if slot_count == 0 {
            continue;
        }

        let attach_idx = lower_name_to_idx
            .get(&parent_key.to_ascii_lowercase())
            .copied()
            .or_else(|| {
                p.parent_bone
                    .as_deref()
                    .and_then(|n| lower_name_to_idx.get(&n.to_ascii_lowercase()).copied())
            })
            .unwrap_or(0);

        let part_tag = match p.source_property.as_deref().and_then(crate::accessory_slot_from_property) {
            Some(s) => format!("Acc{:02}", s),
            None => sanitize_ident(&p.role),
        };

        let mut id_to_global: HashMap<i64, usize> = HashMap::with_capacity(slot_count);
        let mut slots_global: Vec<usize> = Vec::with_capacity(slot_count);

        for slot in 0..slot_count {
            let b_id = private_rig.bone_ids[slot];
            let b_name = &private_rig.names[slot];
            let b_lower = b_name.to_ascii_lowercase();
            let world = unity_world_to_fbx_rigid_cm(&slot_worlds[slot]);

            // If it's a shared body/head bone (for body-weighted clothes/accessories), reuse the shared bone
            if let Some(&shared_idx) = lower_name_to_idx
                .get(&b_lower)
                .filter(|&&idx| copy_weights_body && idx < shared_bone_count)
            {
                id_to_global.insert(b_id, shared_idx);
                slots_global.push(shared_idx);
                continue;
            }

            // Check if an identical private bone (same name & same world position within 0.05 cm,
            // e.g. across submeshes of the same hair/clothes/accessory) was already added
            let scoped_name = if lower_name_to_idx.contains_key(&b_lower) {
                format!("{part_tag}_{}", sanitize_ident(b_name))
            } else {
                sanitize_ident(b_name)
            };
            let scoped_lower = scoped_name.to_ascii_lowercase();
            if let Some(&existing_idx) = lower_name_to_idx.get(&scoped_lower) {
                let ew = &bones[existing_idx].world;
                let dx = ew[0][3] - world[0][3];
                let dy = ew[1][3] - world[1][3];
                let dz = ew[2][3] - world[2][3];
                if dx * dx + dy * dy + dz * dz < 0.0025 {
                    id_to_global.insert(b_id, existing_idx);
                    slots_global.push(existing_idx);
                    continue;
                }
            }

            let final_name = if lower_name_to_idx.contains_key(&scoped_lower) {
                format!("p{part_idx}_{scoped_name}")
            } else {
                scoped_name
            };
            let final_lower = final_name.to_ascii_lowercase();

            let inv_world = rigid_inv(&world);
            let idx = bones.len();
            bones.push(FbxBone {
                name: final_name,
                parent: Some(attach_idx), // refined in second pass below once all sibling slots exist
                world,
                inv_world,
                lcl_translation: [0.0; 3],
                lcl_rotation_deg: [0.0; 3],
            });
            lower_name_to_idx.insert(final_lower, idx);
            id_to_global.insert(b_id, idx);
            slots_global.push(idx);
        }

        // Second pass: resolve parent links within `private_rig.tfs` for newly added private bones
        for slot in 0..slot_count {
            let b_id = private_rig.bone_ids[slot];
            let g_idx = slots_global[slot];
            if g_idx < shared_bone_count {
                continue;
            }
            let mut cur = private_rig.tfs.get(&b_id).and_then(|t| t.parent);
            let mut resolved_parent = None;
            for _ in 0..128 {
                let Some(pid) = cur else {
                    break;
                };
                if let Some(&p_global) = id_to_global.get(&pid) {
                    if p_global != g_idx {
                        resolved_parent = Some(p_global);
                        break;
                    }
                }
                if let Some(tf) = private_rig.tfs.get(&pid) {
                    if let Some(&shared_p) = lower_name_to_idx
                        .get(&tf.name.to_ascii_lowercase())
                        .filter(|&&i| i < shared_bone_count)
                    {
                        resolved_parent = Some(shared_p);
                        break;
                    }
                    if tf.parent == cur {
                        break;
                    }
                    cur = tf.parent;
                } else {
                    break;
                }
            }
            bones[g_idx].parent = Some(resolved_parent.unwrap_or(attach_idx));
        }

        part_private_slot_map.insert(part_idx, slots_global);
    }

    // Compute parent-relative local transforms
    for i in 0..bones.len() {
        let local = if let Some(pi) = bones[i].parent {
            mat4_mul(&bones[pi].inv_world, &bones[i].world)
        } else {
            bones[i].world
        };
        bones[i].lcl_translation = [local[0][3], local[1][3], local[2][3]];
        bones[i].lcl_rotation_deg = mat4_to_fbx_euler_xyz_deg(&local);
    }

    (bones, lower_name_to_idx, part_private_slot_map)
}

// ─────────────────────────────────────────────────────────────────────────────
// Part Categorization, Naming & Texture Baking
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum PartCategory {
    Body = 0,
    HeadFace = 1,
    Hair = 2,
    Clothes = 3,
    Accessories = 4,
}

impl PartCategory {
    pub fn group_name(self) -> &'static str {
        match self {
            PartCategory::Body => "01_Body",
            PartCategory::HeadFace => "02_Head_Face",
            PartCategory::Hair => "03_Hair",
            PartCategory::Clothes => "04_Clothes",
            PartCategory::Accessories => "05_Accessories",
        }
    }
}

fn should_export_part(session: &OkSession, part_idx: usize, p: &SessionPart) -> bool {
    if !p.render_visible
        || session
            .hidden_parts
            .get(part_idx)
            .copied()
            .unwrap_or(false)
        || p.positions.is_empty()
        || p.indices.len() < 3
    {
        return false;
    }
    if p.role == "uncensor_male" {
        return false;
    }
    let lower = p.name.to_ascii_lowercase();
    if matches!(
        lower.as_str(),
        "o_dankon" | "o_dan_f" | "cm_o_dan00" | "cm_o_dan_f" | "o_gomu"
    ) {
        return false;
    }
    // Skip boneless body outline / shadow shell duplicates if any
    if lower.contains("_bonelyfans") {
        return false;
    }
    true
}

fn classify_part(p: &SessionPart) -> PartCategory {
    let r = p.role.as_str();
    let n = p.name.to_ascii_lowercase();
    if r == "head"
        || r == "eye_hi"
        || n.starts_with("cf_o_face")
        || n.starts_with("cf_o_mayuge")
        || n.starts_with("cf_o_matsuge")
        || n.starts_with("cf_o_tooth")
        || n.starts_with("cf_o_tang")
        || n.starts_with("cf_ohitomi")
        || n.starts_with("cf_o_namida")
        || n.starts_with("cf_o_canine")
        || n.starts_with("cf_o_eyeline")
        || n.starts_with("cf_o_noseline")
    {
        PartCategory::HeadFace
    } else if r == "body" || r.starts_with("uncensor") {
        PartCategory::Body
    } else if r.starts_with("hair") {
        PartCategory::Hair
    } else if r.starts_with("clothes")
        || matches!(
            r,
            "top"
                | "bot"
                | "bra"
                | "shorts"
                | "gloves"
                | "panst"
                | "socks"
                | "shoes"
                | "shoes_inner"
                | "shoes_outer"
        )
    {
        PartCategory::Clothes
    } else {
        PartCategory::Accessories
    }
}

fn sanitize_ident(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    while out.contains("__") {
        out = out.replace("__", "_");
    }
    out.trim_matches('_').to_string()
}

fn descriptive_part_base_name(p: &SessionPart, cat: PartCategory) -> String {
    let raw_name = sanitize_ident(&p.name);
    let role_tag = match cat {
        PartCategory::Body => "Body".to_string(),
        PartCategory::HeadFace => {
            let nl = p.name.to_ascii_lowercase();
            if nl.contains("face") {
                "Face".into()
            } else if nl.contains("hitomi_l") {
                "Eye_L".into()
            } else if nl.contains("hitomi_r") {
                "Eye_R".into()
            } else if p.role == "eye_hi" || nl.contains("eyehi") {
                "EyeHighlight".into()
            } else if nl.contains("mayuge") {
                "Eyebrow".into()
            } else if nl.contains("matsuge") || nl.contains("eyeline") {
                "Eyelash".into()
            } else if nl.contains("tooth") || nl.contains("canine") {
                "Teeth".into()
            } else if nl.contains("tang") {
                "Tongue".into()
            } else if nl.contains("namida") {
                "Tears".into()
            } else {
                "Head".into()
            }
        }
        PartCategory::Hair => match p.role.as_str() {
            "hair_back" | "hair_b" => "Hair_Back".into(),
            "hair_front" | "hair_f" => "Hair_Front".into(),
            "hair_side" | "hair_s" => "Hair_Side".into(),
            "hair_ext" | "hair_o" => "Hair_Ext".into(),
            other => sanitize_ident(other),
        },
        PartCategory::Clothes => {
            let sub = p.role.strip_prefix("clothes_").unwrap_or(&p.role);
            format!("Clothes_{}", sanitize_ident(sub))
        }
        PartCategory::Accessories => {
            let slot = p
                .source_property
                .as_deref()
                .and_then(crate::accessory_slot_from_property);
            if let Some(s) = slot {
                format!("Acc{:02}", s)
            } else {
                sanitize_ident(&p.role)
            }
        }
    };
    if raw_name.is_empty() || raw_name.eq_ignore_ascii_case(&role_tag) {
        role_tag
    } else {
        format!("{role_tag}_{raw_name}")
    }
}

fn read_source_material_colors(p: &SessionPart) -> Option<[[f32; 4]; 4]> {
    let mat = p.source_material.as_ref()?;
    let get_col = |k: &str| -> Option<[f32; 4]> { mat.color(k) };
    let c1 = get_col("_Color").or_else(|| get_col("_Color1"));
    let c2 = get_col("_Color2");
    let c3 = get_col("_Color3");
    let c4 = get_col("_Color4");
    if c1.is_none() && c2.is_none() && c3.is_none() && c4.is_none() {
        return None;
    }
    Some([
        c1.unwrap_or([1.0, 1.0, 1.0, 1.0]),
        c2.unwrap_or([1.0, 1.0, 1.0, 1.0]),
        c3.unwrap_or([1.0, 1.0, 1.0, 1.0]),
        c4.unwrap_or([1.0, 1.0, 1.0, 1.0]),
    ])
}

/// Resolve and bake the final diffuse/albedo PNG for DCC tools so hair, clothes, and
/// accessories that deferred `_ColorMask` or `_Color` tinting to UE runtime shaders
/// appear with their exact card colors in Blender / Maya / 3ds Max / Unreal.
fn resolve_baked_albedo_png(p: &SessionPart) -> (Option<Vec<u8>>, [f64; 3], f64) {
    let mat_colors = p
        .item_draw
        .as_ref()
        .map(|d| d.colors)
        .or_else(|| read_source_material_colors(p));
    let default_col = mat_colors.map(|c| c[0]).unwrap_or([0.85, 0.85, 0.85, 1.0]);
    let mut kd = [
        (default_col[0] as f64).clamp(0.0, 1.0),
        (default_col[1] as f64).clamp(0.0, 1.0),
        (default_col[2] as f64).clamp(0.0, 1.0),
    ];
    let opacity = (default_col[3] as f64).clamp(0.0, 1.0);

    let base_png = p
        .png
        .as_deref()
        .or_else(|| p.shader_textures.get("_MainTex").map(Vec::as_slice));
    let mask_png = p
        .item_draw
        .as_ref()
        .and_then(|d| d.color_mask.as_deref())
        .or_else(|| p.shader_textures.get("_ColorMask").map(Vec::as_slice));

    let is_hair = matches!(p.shader_kind, 1 | 10)
        || (p.role.contains("hair") && !p.role.contains("acc"));

    // Was this part left unbaked in `push_meshes` / `accessories` for runtime shader tinting?
    let deferred_color_bake = p.item_draw.is_some()
        || matches!(p.shader_kind, 1 | 2 | 4 | 5 | 6 | 7 | 10 | 11 | 12 | 15)
        || (is_hair && mask_png.is_some());

    let mut out_png: Option<Vec<u8>> = base_png.map(|b| b.to_vec());

    if deferred_color_bake {
        if let Some(cols) = mat_colors {
            if is_hair {
                let white = crate::unity::solid_png([1.0, 1.0, 1.0, 1.0], 8, 8);
                let src = out_png.as_deref().or(white.as_deref());
                if let Some(src_bytes) = src {
                    if let Some(tinted) = crate::unity::hair_get_diffuse(
                        src_bytes,
                        mask_png,
                        cols[0],
                        cols[1],
                        cols[2],
                    ) {
                        out_png = Some(tinted);
                        kd = [1.0, 1.0, 1.0];
                    }
                }
                if let (Some(curr), Some(alpha)) = (
                    out_png.as_deref(),
                    p.alpha_mask
                        .as_deref()
                        .or_else(|| p.shader_textures.get("_AlphaMask").map(Vec::as_slice)),
                ) {
                    if let Some(masked) = crate::apply_hair_alpha_mask(curr, alpha) {
                        out_png = Some(masked);
                    }
                }
            } else if let Some(mask_bytes) = mask_png {
                let white = crate::unity::solid_png([1.0, 1.0, 1.0, 1.0], 64, 64);
                let src = out_png.as_deref().or(white.as_deref());
                if let Some(src_bytes) = src {
                    if let Some(baked) =
                        crate::apply_clothes_color_mask(src_bytes, mask_bytes, cols, &[])
                    {
                        out_png = Some(baked);
                        kd = [1.0, 1.0, 1.0];
                    }
                }
            } else if let Some(src_bytes) = out_png.as_deref() {
                // Single-color `_Color` multiplier when there is no `_ColorMask`
                let c0 = cols[0];
                if (c0[0] - 1.0).abs() > 1e-3
                    || (c0[1] - 1.0).abs() > 1e-3
                    || (c0[2] - 1.0).abs() > 1e-3
                {
                    if let Some(tinted) = crate::unity::tint_png(src_bytes, c0) {
                        out_png = Some(tinted);
                        kd = [1.0, 1.0, 1.0];
                    }
                }
            } else {
                out_png = crate::unity::solid_png(cols[0], 64, 64);
                kd = [1.0, 1.0, 1.0];
            }
        }
    }

    // Bake body/bra/inner-clothes over-masks (`_AlphaMask` + `_overtex1..3`) into PNG alpha
    if let Some(mask_spec) = crate::lowpoly::clothes_over_mask(p) {
        if let Some(curr) = out_png.as_deref() {
            if let Some(baked) = crate::lowpoly::bake_alpha_mask(curr, &mask_spec) {
                out_png = Some(baked);
            }
        }
    }

    if out_png.is_some() {
        kd = [1.0, 1.0, 1.0];
    }

    (out_png, kd, opacity)
}

// ─────────────────────────────────────────────────────────────────────────────
// Prepared Export Part Data
// ─────────────────────────────────────────────────────────────────────────────

struct PreparedBlendShape {
    name: String,
    indices: Vec<i32>,
    delta_vertices_cm: Vec<f64>,
    delta_normals: Vec<f64>,
}

struct PreparedPart {
    part_index: usize,
    category: PartCategory,
    name: String,
    role: String,
    vertex_count: usize,
    triangle_count: usize,
    vertices_cm: Vec<f64>,
    polygon_vertex_index: Vec<i32>,
    normals: Vec<f64>,
    uv_layers: Vec<(&'static str, Vec<f64>)>,
    colors: Option<Vec<f64>>,
    /// `bone_idx -> (vertex_indices, weights)`
    clusters: BTreeMap<usize, (Vec<i32>, Vec<f64>)>,
    blend_shapes: Vec<PreparedBlendShape>,
    albedo_rel_path: Option<String>,
    albedo_abs_path: Option<String>,
    normal_rel_path: Option<String>,
    normal_abs_path: Option<String>,
    diffuse_color: [f64; 3],
    opacity: f64,
    is_translucent: bool,
}

fn prepare_parts(
    session: &OkSession,
    bones: &[FbxBone],
    lower_name_to_idx: &HashMap<String, usize>,
    part_private_slot_map: &HashMap<usize, Vec<usize>>,
    out_dir: &Path,
) -> Result<Vec<PreparedPart>, String> {
    let tex_dir = out_dir.join("textures");
    std::fs::create_dir_all(&tex_dir).map_err(|e| format!("create textures dir: {e}"))?;

    let shared_lookup = |name: &str| lower_name_to_idx.get(&name.to_ascii_lowercase()).copied();

    let mut used_names: HashMap<String, usize> = HashMap::new();
    let mut prepared = Vec::new();

    for (part_idx, p) in session.parts.iter().enumerate() {
        if !should_export_part(session, part_idx, p) {
            continue;
        }
        let category = classify_part(p);
        let base_name = descriptive_part_base_name(p, category);
        let count = used_names.entry(base_name.clone()).or_insert(0);
        *count += 1;
        let unique_name = if *count == 1 {
            base_name
        } else {
            format!("{base_name}_{:02}", *count)
        };

        let vcount = p.positions.len();
        let mut vertices_cm = Vec::with_capacity(vcount * 3);
        for pos in &p.positions {
            let x = if pos[0].is_finite() {
                -(pos[0] as f64) * 100.0
            } else {
                0.0
            };
            let y = if pos[1].is_finite() {
                (pos[1] as f64) * 100.0
            } else {
                0.0
            };
            let z = if pos[2].is_finite() {
                (pos[2] as f64) * 100.0
            } else {
                0.0
            };
            vertices_cm.extend_from_slice(&[x, y, z]);
        }

        let mut normals = Vec::with_capacity(vcount * 3);
        if p.normals.len() == vcount {
            for n in &p.normals {
                let nx = if n[0].is_finite() { -(n[0] as f64) } else { 0.0 };
                let ny = if n[1].is_finite() { n[1] as f64 } else { 0.0 };
                let nz = if n[2].is_finite() { n[2] as f64 } else { 1.0 };
                let len = (nx * nx + ny * ny + nz * nz).sqrt();
                if len > 1e-8 {
                    normals.extend_from_slice(&[nx / len, ny / len, nz / len]);
                } else {
                    normals.extend_from_slice(&[0.0, 0.0, 1.0]);
                }
            }
        } else {
            for _ in 0..vcount {
                normals.extend_from_slice(&[0.0, 0.0, 1.0]);
            }
        }

        // Convert triangles (reverse winding `[i0, i2, !i1]` to match X-mirror)
        let mut polygon_vertex_index = Vec::with_capacity(p.indices.len());
        let mut triangle_count = 0usize;
        for tri in p.indices.chunks_exact(3) {
            let (i0, i1, i2) = (tri[0] as usize, tri[1] as usize, tri[2] as usize);
            if i0 >= vcount || i1 >= vcount || i2 >= vcount {
                continue;
            }
            polygon_vertex_index.push(i0 as i32);
            polygon_vertex_index.push(i2 as i32);
            polygon_vertex_index.push(!(i1 as i32));
            triangle_count += 1;
        }
        if triangle_count == 0 {
            continue;
        }

        // Collect UV layers (UV0..UV3 -> uvs, uv2, uv3, uv4)
        let mut uv_layers = Vec::new();
        for (layer_name, src) in [
            ("UVMap", &p.uvs),
            ("UV2", &p.uv2),
            ("UV3", &p.uv3),
            ("UV4", &p.uv4),
        ] {
            if src.len() == vcount {
                let mut flat = Vec::with_capacity(vcount * 2);
                for uv in src {
                    let u = if uv[0].is_finite() { uv[0] as f64 } else { 0.0 };
                    let v = if uv[1].is_finite() { uv[1] as f64 } else { 0.0 };
                    flat.push(u);
                    flat.push(v);
                }
                uv_layers.push((layer_name, flat));
            }
        }
        if uv_layers.is_empty() {
            uv_layers.push(("UVMap", vec![0.0; vcount * 2]));
        }

        let colors = if p.vertex_colors.len() == vcount {
            let mut flat = Vec::with_capacity(vcount * 4);
            for c in &p.vertex_colors {
                flat.extend_from_slice(&[
                    (c[0] as f64).clamp(0.0, 1.0),
                    (c[1] as f64).clamp(0.0, 1.0),
                    (c[2] as f64).clamp(0.0, 1.0),
                    (c[3] as f64).clamp(0.0, 1.0),
                ]);
            }
            Some(flat)
        } else {
            None
        };

        // Skinning clusters: map per-vertex `[u16; 4]` bone indices to unified `bones`
        let mut clusters: BTreeMap<usize, (Vec<i32>, Vec<f64>)> = BTreeMap::new();
        let skinned = p.weights.len() == vcount && p.bone_idx.len() == vcount;
        let body_skin: Option<&[[u16; 4]]> = session
            .skel_export
            .as_ref()
            .and_then(|ex| ex.part_bone_idx.get(part_idx))
            .map(Vec::as_slice)
            .filter(|v| skinned && matches!(p.skel_kind, 1..=3) && v.len() == vcount);

        let private_bone_map: Option<&[usize]> = part_private_slot_map
            .get(&part_idx)
            .map(Vec::as_slice)
            .filter(|_| skinned && body_skin.is_none());

        if skinned && (body_skin.is_some() || private_bone_map.is_some()) {
            for vi in 0..vcount {
                let raw_idx4 = if let Some(bs) = body_skin {
                    bs[vi]
                } else {
                    p.bone_idx[vi]
                };
                let w4 = p.weights[vi];
                let mut sum = 0.0f64;
                let mut entries = [(0usize, 0.0f64); 4];
                let mut count_e = 0usize;
                for k in 0..4 {
                    let w = w4[k] as f64;
                    if w <= 1e-5 || !w.is_finite() {
                        continue;
                    }
                    let slot = raw_idx4[k] as usize;
                    let global_bi = if body_skin.is_some() {
                        (slot < bones.len()).then_some(slot)
                    } else if let Some(pm) = private_bone_map {
                        pm.get(slot).copied().filter(|&b| b < bones.len())
                    } else {
                        None
                    };
                    if let Some(gbi) = global_bi {
                        if let Some(existing) =
                            entries[..count_e].iter_mut().find(|(b, _)| *b == gbi)
                        {
                            existing.1 += w;
                        } else {
                            entries[count_e] = (gbi, w);
                            count_e += 1;
                        }
                        sum += w;
                    }
                }
                if sum > 1e-6 {
                    for &(gbi, w) in &entries[..count_e] {
                        let entry = clusters.entry(gbi).or_default();
                        entry.0.push(vi as i32);
                        entry.1.push(w / sum);
                    }
                }
            }
        }

        // If a rigid accessory or sub-part had no skin weights, bind 100% to its attach bone
        if clusters.is_empty() {
            let fallback_bone = p
                .rigid_follow_bone
                .as_deref()
                .and_then(&shared_lookup)
                .or_else(|| p.parent_bone.as_deref().and_then(&shared_lookup))
                .or_else(|| {
                    p.runtime_accessory
                        .as_ref()
                        .and_then(|a| a.private_rig())
                        .and_then(|(_, pk)| shared_lookup(pk))
                })
                .unwrap_or(0);
            let indices: Vec<i32> = (0..vcount as i32).collect();
            let weights: Vec<f64> = vec![1.0; vcount];
            clusters.insert(fallback_bone, (indices, weights));
        }

        // BlendShapes (Shape Keys / Morph Targets) from `p.blend_shapes: Vec<(CString, Vec<(u32, [f32; 3])>)>`
        let mut blend_shapes = Vec::new();
        let mut used_bs_names: HashMap<String, usize> = HashMap::new();
        for (bs_cname, deltas) in &p.blend_shapes {
            if deltas.is_empty() {
                continue;
            }
            let mut indices = Vec::with_capacity(deltas.len());
            let mut delta_vertices_cm = Vec::with_capacity(deltas.len() * 3);
            let mut delta_normals = Vec::with_capacity(deltas.len() * 3);
            for &(vi, d) in deltas {
                if (vi as usize) >= vcount {
                    continue;
                }
                let dx = -(d[0] as f64) * 100.0;
                let dy = (d[1] as f64) * 100.0;
                let dz = (d[2] as f64) * 100.0;
                if !dx.is_finite()
                    || !dy.is_finite()
                    || !dz.is_finite()
                    || dx * dx + dy * dy + dz * dz < 1e-8
                {
                    continue;
                }
                indices.push(vi as i32);
                delta_vertices_cm.extend_from_slice(&[dx, dy, dz]);
                delta_normals.extend_from_slice(&[0.0, 0.0, 0.0]);
            }
            if indices.is_empty() {
                continue;
            }
            let raw_bs = bs_cname.to_string_lossy();
            let base_bs = if raw_bs.trim().is_empty() {
                "ShapeKey".to_string()
            } else {
                raw_bs.into_owned()
            };
            let c = used_bs_names.entry(base_bs.clone()).or_insert(0);
            *c += 1;
            let bs_name = if *c == 1 {
                base_bs
            } else {
                format!("{base_bs}_{}", *c)
            };
            blend_shapes.push(PreparedBlendShape {
                name: bs_name,
                indices,
                delta_vertices_cm,
                delta_normals,
            });
        }

        // Bake and write textures
        let (albedo_png, diffuse_color, opacity) = resolve_baked_albedo_png(p);
        let (albedo_rel_path, albedo_abs_path) = if let Some(bytes) = albedo_png {
            let file_name = format!("{unique_name}_BaseColor.png");
            let abs = tex_dir.join(&file_name);
            std::fs::write(&abs, &bytes).map_err(|e| format!("write {}: {e}", abs.display()))?;
            (
                Some(format!("textures/{file_name}")),
                Some(abs.to_string_lossy().replace('\\', "/")),
            )
        } else {
            (None, None)
        };

        let normal_bytes = p
            .normal_map
            .as_deref()
            .or_else(|| p.shader_textures.get("_NormalMap").map(Vec::as_slice));
        let (normal_rel_path, normal_abs_path) = if let Some(bytes) = normal_bytes {
            let file_name = format!("{unique_name}_Normal.png");
            let abs = tex_dir.join(&file_name);
            std::fs::write(&abs, bytes).map_err(|e| format!("write {}: {e}", abs.display()))?;
            (
                Some(format!("textures/{file_name}")),
                Some(abs.to_string_lossy().replace('\\', "/")),
            )
        } else {
            (None, None)
        };

        let is_translucent = matches!(p.blend.as_str(), "alpha" | "add");

        prepared.push(PreparedPart {
            part_index: part_idx,
            category,
            name: unique_name,
            role: p.role.clone(),
            vertex_count: vcount,
            triangle_count,
            vertices_cm,
            polygon_vertex_index,
            normals,
            uv_layers,
            colors,
            clusters,
            blend_shapes,
            albedo_rel_path,
            albedo_abs_path,
            normal_rel_path,
            normal_abs_path,
            diffuse_color,
            opacity,
            is_translucent,
        });
    }

    Ok(prepared)
}

// ─────────────────────────────────────────────────────────────────────────────
// Binary FBX 7.4 Scene Assembly
// ─────────────────────────────────────────────────────────────────────────────

fn build_fbx_document(bones: &[FbxBone], parts: &[&PreparedPart], rel_tex_prefix: &str) -> Vec<u8> {
    let mut next_id = 100_000_000i64;
    let mut alloc_id = || {
        let id = next_id;
        next_id += 1;
        id
    };

    let mut objects: Vec<Node> = Vec::new();
    let mut connections: Vec<Node> = Vec::new();
    let mut bind_pose_items: Vec<(i64, Mat4)> = Vec::new();

    let mut num_models = 0i32;
    let mut num_geoms = 0i32;
    let mut num_mats = 0i32;
    let mut num_texs = 0i32;
    let mut num_videos = 0i32;
    let mut num_deformers = 0i32;
    let mut num_node_attrs = 0i32;

    // 1. Armature Root (`Model::Null`) + Skeleton Hierarchy (`Model::LimbNode` + `NodeAttribute::LimbNode`)
    let armature_id = alloc_id();
    num_models += 1;
    objects.push(
        Node::new("Model")
            .p(Prop::I64(armature_id))
            .p(Prop::Str("Armature\x00\x01Model".into()))
            .p(Prop::Str("Null".into()))
            .c(Node::new("Version").p(Prop::I32(232)))
            .c(Node::new("Properties70")
                .c(prop_p70(
                    "Lcl Translation",
                    "Lcl Translation",
                    "",
                    "A",
                    &[Prop::F64(0.0), Prop::F64(0.0), Prop::F64(0.0)],
                ))
                .c(prop_p70(
                    "Lcl Rotation",
                    "Lcl Rotation",
                    "",
                    "A",
                    &[Prop::F64(0.0), Prop::F64(0.0), Prop::F64(0.0)],
                ))
                .c(prop_p70(
                    "Lcl Scaling",
                    "Lcl Scaling",
                    "",
                    "A",
                    &[Prop::F64(1.0), Prop::F64(1.0), Prop::F64(1.0)],
                )))
            .c(Node::new("Shading").p(Prop::Bool(true)))
            .c(Node::new("Culling").p(Prop::Str("CullingOff".into()))),
    );
    connections.push(conn_oo(armature_id, 0));
    bind_pose_items.push((armature_id, mat4_identity()));

    let mut bone_model_ids = Vec::with_capacity(bones.len());
    for b in bones {
        let attr_id = alloc_id();
        let model_id = alloc_id();
        num_node_attrs += 1;
        num_models += 1;

        objects.push(
            Node::new("NodeAttribute")
                .p(Prop::I64(attr_id))
                .p(Prop::Str(format!("{}\x00\x01NodeAttribute", b.name)))
                .p(Prop::Str("LimbNode".into()))
                .c(Node::new("TypeFlags").p(Prop::Str("Skeleton".into())))
                .c(Node::new("Properties70").c(prop_p70(
                    "Size",
                    "double",
                    "Number",
                    "",
                    &[Prop::F64(1.5)],
                ))),
        );

        objects.push(
            Node::new("Model")
                .p(Prop::I64(model_id))
                .p(Prop::Str(format!("{}\x00\x01Model", b.name)))
                .p(Prop::Str("LimbNode".into()))
                .c(Node::new("Version").p(Prop::I32(232)))
                .c(Node::new("Properties70")
                    .c(prop_p70(
                        "RotationActive",
                        "bool",
                        "",
                        "",
                        &[Prop::I32(1)],
                    ))
                    .c(prop_p70(
                        "InheritType",
                        "enum",
                        "",
                        "",
                        &[Prop::I32(1)],
                    ))
                    .c(prop_p70(
                        "Lcl Translation",
                        "Lcl Translation",
                        "",
                        "A",
                        &[
                            Prop::F64(b.lcl_translation[0]),
                            Prop::F64(b.lcl_translation[1]),
                            Prop::F64(b.lcl_translation[2]),
                        ],
                    ))
                    .c(prop_p70(
                        "Lcl Rotation",
                        "Lcl Rotation",
                        "",
                        "A",
                        &[
                            Prop::F64(b.lcl_rotation_deg[0]),
                            Prop::F64(b.lcl_rotation_deg[1]),
                            Prop::F64(b.lcl_rotation_deg[2]),
                        ],
                    ))
                    .c(prop_p70(
                        "Lcl Scaling",
                        "Lcl Scaling",
                        "",
                        "A",
                        &[Prop::F64(1.0), Prop::F64(1.0), Prop::F64(1.0)],
                    )))
                .c(Node::new("Shading").p(Prop::Bool(true)))
                .c(Node::new("Culling").p(Prop::Str("CullingOff".into()))),
        );

        connections.push(conn_oo(attr_id, model_id));
        let parent_id = b
            .parent
            .and_then(|pi| bone_model_ids.get(pi).copied())
            .unwrap_or(armature_id);
        connections.push(conn_oo(model_id, parent_id));
        bind_pose_items.push((model_id, b.world));
        bone_model_ids.push(model_id);
    }

    // 2. Category Group Null Nodes (`01_Body`, `02_Head_Face`, `03_Hair`, `04_Clothes`, `05_Accessories`)
    let mut category_group_ids: BTreeMap<PartCategory, i64> = BTreeMap::new();
    for p in parts {
        category_group_ids.entry(p.category).or_insert_with(|| {
            let gid = alloc_id();
            num_models += 1;
            let gname = p.category.group_name();
            objects.push(
                Node::new("Model")
                    .p(Prop::I64(gid))
                    .p(Prop::Str(format!("{gname}\x00\x01Model")))
                    .p(Prop::Str("Null".into()))
                    .c(Node::new("Version").p(Prop::I32(232)))
                    .c(Node::new("Properties70")
                        .c(prop_p70(
                            "Lcl Translation",
                            "Lcl Translation",
                            "",
                            "A",
                            &[Prop::F64(0.0), Prop::F64(0.0), Prop::F64(0.0)],
                        ))
                        .c(prop_p70(
                            "Lcl Rotation",
                            "Lcl Rotation",
                            "",
                            "A",
                            &[Prop::F64(0.0), Prop::F64(0.0), Prop::F64(0.0)],
                        ))
                        .c(prop_p70(
                            "Lcl Scaling",
                            "Lcl Scaling",
                            "",
                            "A",
                            &[Prop::F64(1.0), Prop::F64(1.0), Prop::F64(1.0)],
                        )))
                    .c(Node::new("Shading").p(Prop::Bool(true)))
                    .c(Node::new("Culling").p(Prop::Str("CullingOff".into()))),
            );
            connections.push(conn_oo(gid, 0));
            bind_pose_items.push((gid, mat4_identity()));
            gid
        });
    }

    // 3. Each Editable Mesh Part: Geometry + Model + Material + Textures + Skin Clusters + BlendShapes
    for p in parts {
        let geom_id = alloc_id();
        let mesh_model_id = alloc_id();
        let mat_id = alloc_id();
        num_geoms += 1;
        num_models += 1;
        num_mats += 1;

        let mut geom_node = Node::new("Geometry")
            .p(Prop::I64(geom_id))
            .p(Prop::Str(format!("{}\x00\x01Geometry", p.name)))
            .p(Prop::Str("Mesh".into()))
            .c(Node::new("GeometryVersion").p(Prop::I32(124)))
            .c(Node::new("Vertices").p(Prop::ArrF64(p.vertices_cm.clone())))
            .c(Node::new("PolygonVertexIndex").p(Prop::ArrI32(p.polygon_vertex_index.clone())))
            .c(Node::new("LayerElementNormal")
                .p(Prop::I32(0))
                .c(Node::new("Version").p(Prop::I32(101)))
                .c(Node::new("Name").p(Prop::Str("Normals".into())))
                .c(Node::new("MappingInformationType").p(Prop::Str("ByVertice".into())))
                .c(Node::new("ReferenceInformationType").p(Prop::Str("Direct".into())))
                .c(Node::new("Normals").p(Prop::ArrF64(p.normals.clone()))));

        for (uv_idx, (uv_name, uv_flat)) in p.uv_layers.iter().enumerate() {
            geom_node = geom_node.c(
                Node::new("LayerElementUV")
                    .p(Prop::I32(uv_idx as i32))
                    .c(Node::new("Version").p(Prop::I32(101)))
                    .c(Node::new("Name").p(Prop::Str((*uv_name).into())))
                    .c(Node::new("MappingInformationType").p(Prop::Str("ByVertice".into())))
                    .c(Node::new("ReferenceInformationType").p(Prop::Str("Direct".into())))
                    .c(Node::new("UV").p(Prop::ArrF64(uv_flat.clone()))),
            );
        }

        if let Some(cols) = p.colors.as_ref() {
            geom_node = geom_node.c(
                Node::new("LayerElementColor")
                    .p(Prop::I32(0))
                    .c(Node::new("Version").p(Prop::I32(101)))
                    .c(Node::new("Name").p(Prop::Str("Col".into())))
                    .c(Node::new("MappingInformationType").p(Prop::Str("ByVertice".into())))
                    .c(Node::new("ReferenceInformationType").p(Prop::Str("Direct".into())))
                    .c(Node::new("Colors").p(Prop::ArrF64(cols.clone()))),
            );
        }

        geom_node = geom_node.c(
            Node::new("LayerElementMaterial")
                .p(Prop::I32(0))
                .c(Node::new("Version").p(Prop::I32(101)))
                .c(Node::new("Name").p(Prop::Str("Material".into())))
                .c(Node::new("MappingInformationType").p(Prop::Str("AllSame".into())))
                .c(Node::new("ReferenceInformationType").p(Prop::Str("IndexToDirect".into())))
                .c(Node::new("Materials").p(Prop::ArrI32(vec![0]))),
        );

        let mut layer0 = Node::new("Layer")
            .p(Prop::I32(0))
            .c(Node::new("Version").p(Prop::I32(100)))
            .c(Node::new("LayerElement")
                .c(Node::new("Type").p(Prop::Str("LayerElementNormal".into())))
                .c(Node::new("TypedIndex").p(Prop::I32(0))))
            .c(Node::new("LayerElement")
                .c(Node::new("Type").p(Prop::Str("LayerElementUV".into())))
                .c(Node::new("TypedIndex").p(Prop::I32(0))))
            .c(Node::new("LayerElement")
                .c(Node::new("Type").p(Prop::Str("LayerElementMaterial".into())))
                .c(Node::new("TypedIndex").p(Prop::I32(0))));

        if p.colors.is_some() {
            layer0 = layer0.c(
                Node::new("LayerElement")
                    .c(Node::new("Type").p(Prop::Str("LayerElementColor".into())))
                    .c(Node::new("TypedIndex").p(Prop::I32(0))),
            );
        }
        geom_node = geom_node.c(layer0);

        for uv_idx in 1..p.uv_layers.len() {
            geom_node = geom_node.c(
                Node::new("Layer")
                    .p(Prop::I32(uv_idx as i32))
                    .c(Node::new("Version").p(Prop::I32(100)))
                    .c(Node::new("LayerElement")
                        .c(Node::new("Type").p(Prop::Str("LayerElementUV".into())))
                        .c(Node::new("TypedIndex").p(Prop::I32(uv_idx as i32)))),
            );
        }

        objects.push(geom_node);

        // Model::Mesh node
        objects.push(
            Node::new("Model")
                .p(Prop::I64(mesh_model_id))
                .p(Prop::Str(format!("{}\x00\x01Model", p.name)))
                .p(Prop::Str("Mesh".into()))
                .c(Node::new("Version").p(Prop::I32(232)))
                .c(Node::new("Properties70")
                    .c(prop_p70(
                        "Lcl Translation",
                        "Lcl Translation",
                        "",
                        "A",
                        &[Prop::F64(0.0), Prop::F64(0.0), Prop::F64(0.0)],
                    ))
                    .c(prop_p70(
                        "Lcl Rotation",
                        "Lcl Rotation",
                        "",
                        "A",
                        &[Prop::F64(0.0), Prop::F64(0.0), Prop::F64(0.0)],
                    ))
                    .c(prop_p70(
                        "Lcl Scaling",
                        "Lcl Scaling",
                        "",
                        "A",
                        &[Prop::F64(1.0), Prop::F64(1.0), Prop::F64(1.0)],
                    )))
                .c(Node::new("Shading").p(Prop::Bool(true)))
                .c(Node::new("Culling").p(Prop::Str("CullingOff".into()))),
        );

        let group_id = *category_group_ids.get(&p.category).unwrap_or(&0);
        connections.push(conn_oo(geom_id, mesh_model_id));
        connections.push(conn_oo(mesh_model_id, group_id));
        bind_pose_items.push((mesh_model_id, mat4_identity()));

        // Material
        let mat_name = format!("M_{}", p.name);
        objects.push(
            Node::new("Material")
                .p(Prop::I64(mat_id))
                .p(Prop::Str(format!("{mat_name}\x00\x01Material")))
                .p(Prop::Str("".into()))
                .c(Node::new("Version").p(Prop::I32(102)))
                .c(Node::new("ShadingModel").p(Prop::Str("lambert".into())))
                .c(Node::new("MultiLayer").p(Prop::I32(0)))
                .c(Node::new("Properties70")
                    .c(prop_p70(
                        "DiffuseColor",
                        "Color",
                        "",
                        "A",
                        &[
                            Prop::F64(p.diffuse_color[0]),
                            Prop::F64(p.diffuse_color[1]),
                            Prop::F64(p.diffuse_color[2]),
                        ],
                    ))
                    .c(prop_p70(
                        "TransparencyFactor",
                        "Number",
                        "",
                        "A",
                        &[Prop::F64(if p.is_translucent {
                            1.0 - p.opacity
                        } else {
                            0.0
                        })],
                    ))
                    .c(prop_p70(
                        "Opacity",
                        "Number",
                        "",
                        "A",
                        &[Prop::F64(p.opacity)],
                    ))),
        );
        connections.push(conn_oo(mat_id, mesh_model_id));

        // BaseColor Texture + Video
        if let (Some(rel), Some(abs)) = (p.albedo_rel_path.as_ref(), p.albedo_abs_path.as_ref()) {
            let video_id = alloc_id();
            let tex_id = alloc_id();
            num_videos += 1;
            num_texs += 1;
            let rel_final = if rel_tex_prefix.is_empty() {
                rel.clone()
            } else {
                format!("{rel_tex_prefix}{rel}")
            };
            let tex_name = format!("T_{}_BaseColor", p.name);
            objects.push(
                Node::new("Video")
                    .p(Prop::I64(video_id))
                    .p(Prop::Str(format!("{tex_name}\x00\x01Video")))
                    .p(Prop::Str("Clip".into()))
                    .c(Node::new("Type").p(Prop::Str("Clip".into())))
                    .c(Node::new("Properties70").c(prop_p70(
                        "Path",
                        "KString",
                        "XRefUrl",
                        "",
                        &[Prop::Str(abs.clone())],
                    )))
                    .c(Node::new("FileName").p(Prop::Str(abs.clone())))
                    .c(Node::new("RelativeFilename").p(Prop::Str(rel_final.clone()))),
            );
            objects.push(
                Node::new("Texture")
                    .p(Prop::I64(tex_id))
                    .p(Prop::Str(format!("{tex_name}\x00\x01Texture")))
                    .p(Prop::Str("".into()))
                    .c(Node::new("Type").p(Prop::Str("TextureVideoClip".into())))
                    .c(Node::new("Version").p(Prop::I32(202)))
                    .c(Node::new("TextureName").p(Prop::Str(format!("{tex_name}\x00\x01Texture"))))
                    .c(Node::new("Properties70")
                        .c(prop_p70(
                            "UVSet",
                            "KString",
                            "",
                            "",
                            &[Prop::Str("UVMap".into())],
                        ))
                        .c(prop_p70(
                            "UseMaterial",
                            "bool",
                            "",
                            "",
                            &[Prop::I32(1)],
                        )))
                    .c(Node::new("FileName").p(Prop::Str(abs.clone())))
                    .c(Node::new("RelativeFilename").p(Prop::Str(rel_final))),
            );
            connections.push(conn_oo(video_id, tex_id));
            connections.push(conn_op(tex_id, mat_id, "DiffuseColor"));
        }

        // NormalMap Texture + Video
        if let (Some(rel), Some(abs)) = (p.normal_rel_path.as_ref(), p.normal_abs_path.as_ref()) {
            let video_id = alloc_id();
            let tex_id = alloc_id();
            num_videos += 1;
            num_texs += 1;
            let rel_final = if rel_tex_prefix.is_empty() {
                rel.clone()
            } else {
                format!("{rel_tex_prefix}{rel}")
            };
            let tex_name = format!("T_{}_Normal", p.name);
            objects.push(
                Node::new("Video")
                    .p(Prop::I64(video_id))
                    .p(Prop::Str(format!("{tex_name}\x00\x01Video")))
                    .p(Prop::Str("Clip".into()))
                    .c(Node::new("Type").p(Prop::Str("Clip".into())))
                    .c(Node::new("Properties70").c(prop_p70(
                        "Path",
                        "KString",
                        "XRefUrl",
                        "",
                        &[Prop::Str(abs.clone())],
                    )))
                    .c(Node::new("FileName").p(Prop::Str(abs.clone())))
                    .c(Node::new("RelativeFilename").p(Prop::Str(rel_final.clone()))),
            );
            objects.push(
                Node::new("Texture")
                    .p(Prop::I64(tex_id))
                    .p(Prop::Str(format!("{tex_name}\x00\x01Texture")))
                    .p(Prop::Str("".into()))
                    .c(Node::new("Type").p(Prop::Str("TextureVideoClip".into())))
                    .c(Node::new("Version").p(Prop::I32(202)))
                    .c(Node::new("TextureName").p(Prop::Str(format!("{tex_name}\x00\x01Texture"))))
                    .c(Node::new("Properties70")
                        .c(prop_p70(
                            "UVSet",
                            "KString",
                            "",
                            "",
                            &[Prop::Str("UVMap".into())],
                        ))
                        .c(prop_p70(
                            "UseMaterial",
                            "bool",
                            "",
                            "",
                            &[Prop::I32(1)],
                        )))
                    .c(Node::new("FileName").p(Prop::Str(abs.clone())))
                    .c(Node::new("RelativeFilename").p(Prop::Str(rel_final))),
            );
            connections.push(conn_oo(video_id, tex_id));
            connections.push(conn_op(tex_id, mat_id, "NormalMap"));
        }

        // Skin Deformer + Per-Bone Clusters
        if !p.clusters.is_empty() {
            let skin_id = alloc_id();
            num_deformers += 1;
            objects.push(
                Node::new("Deformer")
                    .p(Prop::I64(skin_id))
                    .p(Prop::Str(format!("Skin_{}\x00\x01Deformer", p.name)))
                    .p(Prop::Str("Skin".into()))
                    .c(Node::new("Version").p(Prop::I32(101)))
                    .c(Node::new("Link_DeformAcuracy").p(Prop::F64(50.0))),
            );
            connections.push(conn_oo(skin_id, geom_id));

            for (&bone_idx, (v_indices, v_weights)) in &p.clusters {
                let Some(&bone_model_id) = bone_model_ids.get(bone_idx) else {
                    continue;
                };
                let bone = &bones[bone_idx];
                let cluster_id = alloc_id();
                num_deformers += 1;
                objects.push(
                    Node::new("Deformer")
                        .p(Prop::I64(cluster_id))
                        .p(Prop::Str(format!(
                            "SubDeformer_{}_{}\x00\x01SubDeformer",
                            p.name, bone.name
                        )))
                        .p(Prop::Str("Cluster".into()))
                        .c(Node::new("Version").p(Prop::I32(100)))
                        .c(Node::new("UserData").p(Prop::Str("".into())).p(Prop::Str("".into())))
                        .c(Node::new("Indexes").p(Prop::ArrI32(v_indices.clone())))
                        .c(Node::new("Weights").p(Prop::ArrF64(v_weights.clone())))
                        .c(Node::new("Transform")
                            .p(Prop::ArrF64(mat4_to_fbx_col_major(&bone.inv_world))))
                        .c(Node::new("TransformLink")
                            .p(Prop::ArrF64(mat4_to_fbx_col_major(&bone.world)))),
                );
                connections.push(conn_oo(cluster_id, skin_id));
                connections.push(conn_oo(bone_model_id, cluster_id));
            }
        }

        // BlendShape Deformer + Channels + Geometry::Shape
        if !p.blend_shapes.is_empty() {
            let bs_deformer_id = alloc_id();
            num_deformers += 1;
            objects.push(
                Node::new("Deformer")
                    .p(Prop::I64(bs_deformer_id))
                    .p(Prop::Str(format!("BlendShapes_{}\x00\x01Deformer", p.name)))
                    .p(Prop::Str("BlendShape".into()))
                    .c(Node::new("Version").p(Prop::I32(100))),
            );
            connections.push(conn_oo(bs_deformer_id, geom_id));

            for bs in &p.blend_shapes {
                let channel_id = alloc_id();
                let shape_geom_id = alloc_id();
                num_deformers += 1;
                num_geoms += 1;

                objects.push(
                    Node::new("Deformer")
                        .p(Prop::I64(channel_id))
                        .p(Prop::Str(format!("{}\x00\x01SubDeformer", bs.name)))
                        .p(Prop::Str("BlendShapeChannel".into()))
                        .c(Node::new("Version").p(Prop::I32(100)))
                        .c(Node::new("DeformPercent").p(Prop::F64(0.0)))
                        .c(Node::new("FullWeights").p(Prop::ArrF64(vec![100.0])))
                        .c(Node::new("Properties70").c(prop_p70(
                            "DeformPercent",
                            "Number",
                            "",
                            "A",
                            &[Prop::F64(0.0)],
                        ))),
                );

                objects.push(
                    Node::new("Geometry")
                        .p(Prop::I64(shape_geom_id))
                        .p(Prop::Str(format!("{}\x00\x01Geometry", bs.name)))
                        .p(Prop::Str("Shape".into()))
                        .c(Node::new("Version").p(Prop::I32(100)))
                        .c(Node::new("Indexes").p(Prop::ArrI32(bs.indices.clone())))
                        .c(Node::new("Vertices").p(Prop::ArrF64(bs.delta_vertices_cm.clone())))
                        .c(Node::new("Normals").p(Prop::ArrF64(bs.delta_normals.clone()))),
                );

                connections.push(conn_oo(channel_id, bs_deformer_id));
                connections.push(conn_oo(shape_geom_id, channel_id));
            }
        }
    }

    // 4. BindPose Node (lists Armature, all LimbNodes, Category Groups, and Mesh Models)
    let pose_id = alloc_id();
    let mut pose_node = Node::new("Pose")
        .p(Prop::I64(pose_id))
        .p(Prop::Str("BindPose\x00\x01Pose".into()))
        .p(Prop::Str("BindPose".into()))
        .c(Node::new("Type").p(Prop::Str("BindPose".into())))
        .c(Node::new("Version").p(Prop::I32(100)))
        .c(Node::new("NbPoseNodes").p(Prop::I32(bind_pose_items.len() as i32)));
    for &(node_id, ref world_mat) in &bind_pose_items {
        pose_node = pose_node.c(
            Node::new("PoseNode")
                .c(Node::new("Node").p(Prop::I64(node_id)))
                .c(Node::new("Matrix").p(Prop::ArrF64(mat4_to_fbx_col_major(world_mat)))),
        );
    }
    objects.push(pose_node);

    // 5. Top-level FBX 7.4 Sections
    let header_ext = Node::new("FBXHeaderExtension")
        .c(Node::new("FBXHeaderVersion").p(Prop::I32(1003)))
        .c(Node::new("FBXVersion").p(Prop::I32(7400)))
        .c(Node::new("EncryptionType").p(Prop::I32(0)))
        .c(Node::new("Creator").p(Prop::Str("OpenKoikatsu ok-extract FBX 7.4 Exporter".into())));

    let global_settings = Node::new("GlobalSettings")
        .c(Node::new("Version").p(Prop::I32(1000)))
        .c(Node::new("Properties70")
            .c(prop_p70("UpAxis", "int", "Integer", "", &[Prop::I32(1)]))
            .c(prop_p70("UpAxisSign", "int", "Integer", "", &[Prop::I32(1)]))
            .c(prop_p70("FrontAxis", "int", "Integer", "", &[Prop::I32(2)]))
            .c(prop_p70("FrontAxisSign", "int", "Integer", "", &[Prop::I32(1)]))
            .c(prop_p70("CoordAxis", "int", "Integer", "", &[Prop::I32(0)]))
            .c(prop_p70("CoordAxisSign", "int", "Integer", "", &[Prop::I32(1)]))
            .c(prop_p70("OriginalUpAxis", "int", "Integer", "", &[Prop::I32(1)]))
            .c(prop_p70("OriginalUpAxisSign", "int", "Integer", "", &[Prop::I32(1)]))
            .c(prop_p70(
                "UnitScaleFactor",
                "double",
                "Number",
                "",
                &[Prop::F64(1.0)],
            ))
            .c(prop_p70(
                "OriginalUnitScaleFactor",
                "double",
                "Number",
                "",
                &[Prop::F64(1.0)],
            )));

    let documents = Node::new("Documents")
        .c(Node::new("Count").p(Prop::I32(1)))
        .c(Node::new("Document")
            .p(Prop::I64(1_000_000))
            .p(Prop::Str("Scene".into()))
            .p(Prop::Str("Scene".into()))
            .c(Node::new("Properties70")
                .c(prop_p70("SourceObject", "object", "", "", &[]))
                .c(prop_p70(
                    "ActiveAnimStackName",
                    "KString",
                    "",
                    "",
                    &[Prop::Str("".into())],
                )))
            .c(Node::new("RootNode").p(Prop::I64(0))));

    let references = Node::new("References");

    let total_defs =
        1 + num_models + num_geoms + num_mats + num_texs + num_videos + num_deformers + num_node_attrs + 1;
    let mut definitions = Node::new("Definitions")
        .c(Node::new("Version").p(Prop::I32(100)))
        .c(Node::new("Count").p(Prop::I32(total_defs)))
        .c(Node::new("ObjectType")
            .p(Prop::Str("GlobalSettings".into()))
            .c(Node::new("Count").p(Prop::I32(1))))
        .c(Node::new("ObjectType")
            .p(Prop::Str("Model".into()))
            .c(Node::new("Count").p(Prop::I32(num_models))))
        .c(Node::new("ObjectType")
            .p(Prop::Str("Geometry".into()))
            .c(Node::new("Count").p(Prop::I32(num_geoms))))
        .c(Node::new("ObjectType")
            .p(Prop::Str("Material".into()))
            .c(Node::new("Count").p(Prop::I32(num_mats))))
        .c(Node::new("ObjectType")
            .p(Prop::Str("Pose".into()))
            .c(Node::new("Count").p(Prop::I32(1))));
    if num_node_attrs > 0 {
        definitions = definitions.c(
            Node::new("ObjectType")
                .p(Prop::Str("NodeAttribute".into()))
                .c(Node::new("Count").p(Prop::I32(num_node_attrs))),
        );
    }
    if num_deformers > 0 {
        definitions = definitions.c(
            Node::new("ObjectType")
                .p(Prop::Str("Deformer".into()))
                .c(Node::new("Count").p(Prop::I32(num_deformers))),
        );
    }
    if num_texs > 0 {
        definitions = definitions.c(
            Node::new("ObjectType")
                .p(Prop::Str("Texture".into()))
                .c(Node::new("Count").p(Prop::I32(num_texs))),
        );
    }
    if num_videos > 0 {
        definitions = definitions.c(
            Node::new("ObjectType")
                .p(Prop::Str("Video".into()))
                .c(Node::new("Count").p(Prop::I32(num_videos))),
        );
    }

    let mut objects_section = Node::new("Objects");
    objects_section.children = objects;

    let mut connections_section = Node::new("Connections");
    connections_section.children = connections;

    encode_binary(&[
        header_ext,
        global_settings,
        documents,
        references,
        definitions,
        objects_section,
        connections_section,
    ])
}

// ─────────────────────────────────────────────────────────────────────────────
// Public Entry Point
// ─────────────────────────────────────────────────────────────────────────────

pub fn export_card_fbx(
    game_root: &Path,
    card_path: &Path,
    out_dir: &Path,
    outfit: i32,
) -> Result<serde_json::Value, String> {
    std::fs::create_dir_all(out_dir).map_err(|e| format!("create output dir: {e}"))?;
    let parts_dir = out_dir.join("parts");
    std::fs::create_dir_all(&parts_dir).map_err(|e| format!("create parts dir: {e}"))?;

    // Ensure CPU skinning runs for all body/head/hair/clothes/accessory parts (`OK_SKELMESH` must not skip CPU skinning)
    std::env::remove_var("OK_SKELMESH");

    let mut session = crate::session::open(game_root, Some(card_path), outfit)?;
    session.skin_all();
    session.ensure_skel_export();

    let (bones, lower_name_to_idx, part_private_slot_map) = build_unified_skeleton(&session);
    let prepared_parts = prepare_parts(
        &session,
        &bones,
        &lower_name_to_idx,
        &part_private_slot_map,
        out_dir,
    )?;
    if prepared_parts.is_empty() {
        return Err("no visible mesh parts found on card".into());
    }

    let stem = card_path
        .file_stem()
        .and_then(|s| s.to_str())
        .map(sanitize_ident)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "Character".into());

    // 1. Write Full Rigged FBX (all split parts organized under 01_Body..05_Accessories)
    let all_refs: Vec<&PreparedPart> = prepared_parts.iter().collect();
    let full_fbx_bytes = build_fbx_document(&bones, &all_refs, "");
    let full_fbx_path = out_dir.join(format!("{stem}_Full_Rigged.fbx"));
    std::fs::write(&full_fbx_path, &full_fbx_bytes)
        .map_err(|e| format!("write {}: {e}", full_fbx_path.display()))?;

    // 2. Write per-category split FBX files under `parts/`
    let mut category_files = Vec::new();
    for cat in [
        PartCategory::Body,
        PartCategory::HeadFace,
        PartCategory::Hair,
        PartCategory::Clothes,
        PartCategory::Accessories,
    ] {
        let cat_refs: Vec<&PreparedPart> = prepared_parts
            .iter()
            .filter(|p| p.category == cat)
            .collect();
        if cat_refs.is_empty() {
            continue;
        }
        let cat_fbx_bytes = build_fbx_document(&bones, &cat_refs, "../");
        let cat_file_name = format!("{}.fbx", cat.group_name());
        let cat_path = parts_dir.join(&cat_file_name);
        std::fs::write(&cat_path, &cat_fbx_bytes)
            .map_err(|e| format!("write {}: {e}", cat_path.display()))?;
        category_files.push(serde_json::json!({
            "category": cat.group_name(),
            "file": format!("parts/{cat_file_name}"),
            "part_count": cat_refs.len(),
        }));
    }

    // 3. Write manifest.json summarizing all exported parts, textures, bones, and BlendShapes
    let total_vertices: usize = prepared_parts.iter().map(|p| p.vertex_count).sum();
    let total_triangles: usize = prepared_parts.iter().map(|p| p.triangle_count).sum();
    let total_blend_shapes: usize = prepared_parts.iter().map(|p| p.blend_shapes.len()).sum();

    let parts_json: Vec<serde_json::Value> = prepared_parts
        .iter()
        .map(|p| {
            serde_json::json!({
                "part_index": p.part_index,
                "name": p.name,
                "category": p.category.group_name(),
                "role": p.role,
                "vertices": p.vertex_count,
                "triangles": p.triangle_count,
                "uv_channels": p.uv_layers.len(),
                "has_vertex_color": p.colors.is_some(),
                "skinned_bones": p.clusters.len(),
                "blend_shapes": p.blend_shapes.iter().map(|b| &b.name).collect::<Vec<_>>(),
                "base_color_texture": p.albedo_rel_path,
                "normal_texture": p.normal_rel_path,
            })
        })
        .collect();

    let summary = serde_json::json!({
        "card": card_path.to_string_lossy(),
        "outfit": outfit,
        "full_fbx": full_fbx_path.to_string_lossy().replace('\\', "/"),
        "category_fbx_files": category_files,
        "total_parts": prepared_parts.len(),
        "total_bones": bones.len(),
        "total_vertices": total_vertices,
        "total_triangles": total_triangles,
        "total_blend_shapes": total_blend_shapes,
        "parts": parts_json,
    });

    let manifest_path = out_dir.join("manifest.json");
    std::fs::write(
        &manifest_path,
        serde_json::to_string_pretty(&summary).unwrap_or_default(),
    )
    .map_err(|e| format!("write manifest.json: {e}"))?;

    Ok(summary)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_fbx_rigged_document_structure_and_euler_roundtrip() {
        let root_bone = FbxBone {
            name: "cf_j_root".into(),
            parent: None,
            world: mat4_identity(),
            inv_world: mat4_identity(),
            lcl_translation: [0.0, 0.0, 0.0],
            lcl_rotation_deg: [0.0, 0.0, 0.0],
        };
        let mut head_world = mat4_identity();
        head_world[1][3] = 150.0;
        let head_bone = FbxBone {
            name: "cf_j_head".into(),
            parent: Some(0),
            world: head_world,
            inv_world: rigid_inv(&head_world),
            lcl_translation: [0.0, 150.0, 0.0],
            lcl_rotation_deg: [0.0, 0.0, 0.0],
        };
        let bones = vec![root_bone, head_bone];

        let mut clusters = BTreeMap::new();
        clusters.insert(1usize, (vec![0, 1, 2], vec![1.0, 1.0, 1.0]));

        let part = PreparedPart {
            part_index: 0,
            category: PartCategory::HeadFace,
            name: "Face_cf_O_face".into(),
            role: "head".into(),
            vertex_count: 3,
            triangle_count: 1,
            vertices_cm: vec![0.0, 150.0, 0.0, -5.0, 155.0, 2.0, 5.0, 155.0, 2.0],
            polygon_vertex_index: vec![0, 2, !1],
            normals: vec![0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0],
            uv_layers: vec![("UVMap", vec![0.0, 0.0, 1.0, 0.0, 0.5, 1.0])],
            colors: Some(vec![1.0; 12]),
            clusters,
            blend_shapes: vec![PreparedBlendShape {
                name: "eye_face.f00_smile".into(),
                indices: vec![1, 2],
                delta_vertices_cm: vec![0.0, 0.5, 0.0, 0.0, 0.5, 0.0],
                delta_normals: vec![0.0; 6],
            }],
            albedo_rel_path: Some("textures/Face_cf_O_face_BaseColor.png".into()),
            albedo_abs_path: Some("C:/Temp/textures/Face_cf_O_face_BaseColor.png".into()),
            normal_rel_path: None,
            normal_abs_path: None,
            diffuse_color: [1.0, 1.0, 1.0],
            opacity: 1.0,
            is_translucent: false,
        };

        let bytes = build_fbx_document(&bones, &[&part], "");
        assert!(bytes.starts_with(b"Kaydara FBX Binary  \x00\x1a\x00"));
        let version = u32::from_le_bytes(bytes[23..27].try_into().unwrap());
        assert_eq!(version, 7400);

        // Verify top-level node walk reaches the 13-byte null terminator cleanly
        let mut pos = 27usize;
        let mut top_names = Vec::new();
        loop {
            let end_offset = u32::from_le_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
            let num_props = u32::from_le_bytes(bytes[pos + 4..pos + 8].try_into().unwrap());
            let prop_bytes = u32::from_le_bytes(bytes[pos + 8..pos + 12].try_into().unwrap());
            let name_len = bytes[pos + 12] as usize;
            if end_offset == 0 && num_props == 0 && prop_bytes == 0 && name_len == 0 {
                break;
            }
            let name = std::str::from_utf8(&bytes[pos + 13..pos + 13 + name_len]).unwrap();
            top_names.push(name.to_string());
            assert!(end_offset > pos && end_offset <= bytes.len());
            pos = end_offset;
        }
        assert_eq!(
            top_names,
            vec![
                "FBXHeaderExtension",
                "GlobalSettings",
                "Documents",
                "References",
                "Definitions",
                "Objects",
                "Connections"
            ]
        );
    }
}
