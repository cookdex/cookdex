//! Recipe ZIP interchange with optional device-local shopping setup (schema 1 input, schema 2 output). Never extracts paths to disk.
use crate::recipe::{MAX_COLLECTION_BYTES, MAX_ITEMS, Recipe};
use crate::services::{Error, Result};
use std::{collections::HashSet, io::Read};

pub const MAX_SETUP_BYTES: usize = 4 * 1024 * 1024;
const SETUP_ENTRY: &str = ".cookdex-shopping.json";
pub const MAX_ZIP_BYTES: usize = MAX_COLLECTION_BYTES + MAX_ITEMS * 286 + 22 + MAX_SETUP_BYTES;
fn bad() -> Error {
    Error::InvalidZip
}
fn u16_at(b: &[u8], p: usize) -> Result<usize> {
    Ok(u16::from_le_bytes(
        b.get(p..p + 2)
            .ok_or_else(bad)?
            .try_into()
            .map_err(|_| bad())?,
    ) as usize)
}
fn u32_at(b: &[u8], p: usize) -> Result<usize> {
    Ok(u32::from_le_bytes(
        b.get(p..p + 4)
            .ok_or_else(bad)?
            .try_into()
            .map_err(|_| bad())?,
    ) as usize)
}
fn id_ok(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 100
        && id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
}
pub fn validate_collection(recipes: &[Recipe]) -> Result<()> {
    if recipes.len() > MAX_ITEMS {
        return Err(Error::Limit);
    }
    let mut ids = HashSet::new();
    let mut size = br#"{"schemaVersion":1,"recipes":[],"shopping":[],"deletedRecipes":[]}"#.len()
        + recipes.len().saturating_sub(1);
    for recipe in recipes {
        if !id_ok(&recipe.id.0) || !ids.insert(&recipe.id.0) {
            return Err(Error::InvalidData);
        }
        size += recipe.to_json()?.len();
        if size > MAX_COLLECTION_BYTES {
            return Err(Error::Limit);
        }
    }
    Ok(())
}
fn put16(b: &mut [u8], p: usize, n: usize) {
    b[p..p + 2].copy_from_slice(&(n as u16).to_le_bytes());
}
fn put32(b: &mut [u8], p: usize, n: usize) {
    b[p..p + 4].copy_from_slice(&(n as u32).to_le_bytes());
}
pub fn write(recipes: &[Recipe]) -> Result<Vec<u8>> {
    write_with_setup(recipes, None)
}
pub fn write_with_setup(
    recipes: &[Recipe],
    setup: Option<&crate::shopping_categories::Setup>,
) -> Result<Vec<u8>> {
    validate_collection(recipes)?;
    let mut entries = recipes
        .iter()
        .map(|r| Ok((format!("{}.json", r.id.0), r.to_json()?)))
        .collect::<Result<Vec<_>>>()?;
    if let Some(setup) = setup {
        setup.validate()?;
        let data = serde_json::to_vec(setup).map_err(|_| Error::InvalidData)?;
        if data.len() > MAX_SETUP_BYTES {
            return Err(Error::Limit);
        }
        entries.push((SETUP_ENTRY.into(), data));
    }
    let mut out = vec![];
    let mut directory = vec![];
    for (name, data) in &entries {
        let crc = crc32fast::hash(&data) as usize;
        let mut local = vec![0; 30];
        put32(&mut local, 0, 0x04034b50);
        put16(&mut local, 4, 20);
        put16(&mut local, 6, 0x800);
        put32(&mut local, 14, crc);
        put32(&mut local, 18, data.len());
        put32(&mut local, 22, data.len());
        put16(&mut local, 26, name.len());
        let mut central = vec![0; 46];
        put32(&mut central, 0, 0x02014b50);
        put16(&mut central, 4, 20);
        put16(&mut central, 6, 20);
        put16(&mut central, 8, 0x800);
        put32(&mut central, 16, crc);
        put32(&mut central, 20, data.len());
        put32(&mut central, 24, data.len());
        put16(&mut central, 28, name.len());
        put32(&mut central, 42, out.len());
        out.extend(local);
        out.extend(name.as_bytes());
        out.extend(data);
        directory.extend(central);
        directory.extend(name.as_bytes());
    }
    let mut end = vec![0; 22];
    put32(&mut end, 0, 0x06054b50);
    put16(&mut end, 8, entries.len());
    put16(&mut end, 10, entries.len());
    put32(&mut end, 12, directory.len());
    put32(&mut end, 16, out.len());
    out.extend(directory);
    out.extend(end);
    if out.len() > MAX_ZIP_BYTES {
        return Err(Error::Limit);
    }
    Ok(out)
}
pub fn read(b: &[u8]) -> Result<Vec<Recipe>> {
    Ok(read_with_setup(b)?.0)
}
pub fn read_with_setup(
    b: &[u8],
) -> Result<(Vec<Recipe>, Option<crate::shopping_categories::Setup>)> {
    if b.len() > MAX_ZIP_BYTES {
        return Err(Error::Limit);
    }
    if b.len() < 22 {
        return Err(bad());
    }
    let end = (b.len().saturating_sub(65557)..=b.len() - 22)
        .rev()
        .find(|&p| {
            u32_at(b, p) == Ok(0x06054b50) && u16_at(b, p + 20).is_ok_and(|n| p + 22 + n == b.len())
        })
        .ok_or_else(bad)?;
    let count = u16_at(b, end + 10)?;
    let start = u32_at(b, end + 16)?;
    if count > MAX_ITEMS + 1 {
        return Err(Error::Limit);
    }
    if u16_at(b, end + 4)? != 0
        || u16_at(b, end + 6)? != 0
        || u16_at(b, end + 8)? != count
        || start + u32_at(b, end + 12)? != end
    {
        return Err(bad());
    }
    let mut p = start;
    let mut total = 0;
    let mut ranges = vec![];
    let mut names = HashSet::new();
    let mut recipes = vec![];
    let mut setup = None;
    for _ in 0..count {
        if p + 46 > end || u32_at(b, p)? != 0x02014b50 {
            return Err(bad());
        }
        let (flags, method, crc, packed, len, n, extra, comment, offset) = (
            u16_at(b, p + 8)?,
            u16_at(b, p + 10)?,
            u32_at(b, p + 16)?,
            u32_at(b, p + 20)?,
            u32_at(b, p + 24)?,
            u16_at(b, p + 28)?,
            u16_at(b, p + 30)?,
            u16_at(b, p + 32)?,
            u32_at(b, p + 42)?,
        );
        if p + 46 + n + extra + comment > end || u16_at(b, p + 34)? != 0 {
            return Err(bad());
        }
        let name = std::str::from_utf8(&b[p + 46..p + 46 + n]).map_err(|_| bad())?;
        let is_setup = name == SETUP_ENTRY;
        let id = if is_setup {
            ""
        } else {
            name.strip_suffix(".json")
                .filter(|id| id_ok(id))
                .ok_or_else(bad)?
        };
        if is_setup && len > MAX_SETUP_BYTES {
            return Err(Error::Limit);
        }
        if !names.insert(name) || flags & !0x808 != 0 || ![0, 8].contains(&method) {
            return Err(bad());
        }
        total += len;
        if len > MAX_COLLECTION_BYTES || total > MAX_ZIP_BYTES {
            return Err(Error::Limit);
        }
        if offset + 30 > start || u32_at(b, offset)? != 0x04034b50 {
            return Err(bad());
        }
        let local_n = u16_at(b, offset + 26)?;
        let data_start = offset + 30 + local_n + u16_at(b, offset + 28)?;
        if data_start + packed > start
            || b.get(offset + 30..offset + 30 + local_n) != Some(name.as_bytes())
            || u16_at(b, offset + 6)? != flags
            || u16_at(b, offset + 8)? != method
        {
            return Err(bad());
        }
        if flags & 8 == 0
            && (u32_at(b, offset + 14)? != crc
                || u32_at(b, offset + 18)? != packed
                || u32_at(b, offset + 22)? != len)
        {
            return Err(bad());
        }
        let mut local_end = data_start + packed;
        if flags & 8 != 0 {
            // A streaming ZIP descriptor is part of its local entry range.
            let d = local_end
                + if u32_at(b, local_end)? == 0x08074b50 {
                    4
                } else {
                    0
                };
            if d + 12 > start
                || u32_at(b, d)? != crc
                || u32_at(b, d + 4)? != packed
                || u32_at(b, d + 8)? != len
            {
                return Err(bad());
            }
            local_end = d + 12;
        }
        ranges.push((offset, local_end));
        let input = &b[data_start..data_start + packed];
        let data = if method == 0 {
            input.to_vec()
        } else {
            let mut decoder = flate2::read::DeflateDecoder::new(input);
            let mut data = Vec::new();
            decoder
                .by_ref()
                .take(len as u64 + 1)
                .read_to_end(&mut data)
                .map_err(|_| bad())?;
            if decoder.total_in() as usize != packed {
                return Err(bad());
            }
            data
        };
        if data.len() != len || crc32fast::hash(&data) as usize != crc {
            return Err(bad());
        }
        if is_setup {
            let value: crate::shopping_categories::Setup =
                serde_json::from_slice(&data).map_err(|_| bad())?;
            value.validate().map_err(|_| bad())?;
            setup = Some(value);
        } else {
            let recipe = Recipe::from_json(&data)?;
            if recipe.id.0 != id {
                return Err(bad());
            }
            recipes.push(recipe);
        }
        p += 46 + n + extra + comment;
    }
    if p != end {
        return Err(bad());
    }
    ranges.sort_unstable();
    if ranges.windows(2).any(|pair| pair[1].0 < pair[0].1) {
        return Err(bad());
    }
    validate_collection(&recipes)?;
    Ok((recipes, setup))
}
