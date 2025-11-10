use anyhow::{anyhow, Context, Result};
use rand::{distributions::Alphanumeric, Rng};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

pub fn temp_file(prefix: &str, create: bool) -> Result<PathBuf> {
    let mut path = std::env::temp_dir();
    let suffix: String = rand::thread_rng()
        .sample_iter(Alphanumeric)
        .take(8)
        .map(char::from)
        .collect();
    let filename = format!("{}-{}", prefix, suffix);
    path.push(filename);
    if create {
        File::create(&path).with_context(|| format!("无法创建临时文件 {}", path.display()))?;
    }
    Ok(path)
}

pub fn write_bytes<P: AsRef<Path>>(path: P, data: &[u8]) -> Result<()> {
    fs::write(&path, data).with_context(|| format!("写入文件失败: {}", path.as_ref().display()))
}

pub fn append_bytes<P: AsRef<Path>>(path: P, data: &[u8]) -> Result<()> {
    let mut file = OpenOptions::new()
        .append(true)
        .create(true)
        .open(&path)
        .with_context(|| format!("以追加方式打开文件失败: {}", path.as_ref().display()))?;
    file.write_all(data)
        .with_context(|| format!("追加写入失败: {}", path.as_ref().display()))?;
    file.flush()
        .with_context(|| format!("刷新写入失败: {}", path.as_ref().display()))
}

pub fn read_bytes<P: AsRef<Path>>(path: P) -> Result<Vec<u8>> {
    let mut buffer = Vec::new();
    let mut file = OpenOptions::new()
        .read(true)
        .open(&path)
        .with_context(|| format!("打开文件失败: {}", path.as_ref().display()))?;
    file.read_to_end(&mut buffer)
        .with_context(|| format!("读取文件失败: {}", path.as_ref().display()))?;
    Ok(buffer)
}

pub fn cleanup_file<P: AsRef<Path>>(path: P) -> Result<()> {
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(anyhow!(
            "删除文件失败: {} -> {err}",
            path.as_ref().display()
        )),
    }
}

pub fn random_bytes(len: usize) -> Vec<u8> {
    rand::thread_rng()
        .sample_iter(rand::distributions::Standard)
        .take(len)
        .collect()
}

pub fn ensure_syscall_success(ret: i64, context: &str) -> Result<i64> {
    if ret < 0 {
        Err(anyhow!("{context} -> syscall 返回 {ret}"))
    } else {
        Ok(ret)
    }
}
