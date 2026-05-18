use std::fs;
use std::path::Path;
use std::time::{Duration, SystemTime};

fn main() {
    println!("Starting cleanup of empty rooms...");
    let recordings_dir = Path::new("recordings");

    if !recordings_dir.exists() {
        println!("No recordings directory found. Nothing to clean.");
        return;
    }

    let mut deleted_count = 0;
    
    // Define what "older" means (e.g., modified more than 1 hour ago)
    let threshold = SystemTime::now() - Duration::from_secs(3600);

    for entry in fs::read_dir(recordings_dir).expect("Failed to read recordings dir") {
        let entry = entry.expect("Failed to read entry");
        let path = entry.path();

        if path.is_dir() {
            // Detect any file whose name contains "test"
            let mut has_test = false;
            if let Ok(room_entries) = fs::read_dir(&path) {
                for room_entry in room_entries.flatten() {
                    let file_path = room_entry.path();
                    if file_path.is_file() {
                        if let Some(name_os) = file_path.file_name() {
                            if let Some(name_str) = name_os.to_str() {
                                if name_str.contains("test") {
                                    has_test = true;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            if has_test {
                println!("Deleting room with test.webm: {:?}", path);
                if let Err(e) = fs::remove_dir_all(&path) {
                    eprintln!("Failed to delete {:?}: {}", path, e);
                } else {
                    deleted_count += 1;
                }
                continue;
            }

            // After test check, handle completely empty folders
            // If the directory has no entries, delete it immediately
            if let Ok(mut dir_iter) = fs::read_dir(&path) {
                if dir_iter.next().is_none() {
                    println!("Deleting empty room: {:?}", path);
                    if let Err(e) = fs::remove_dir_all(&path) {
                        eprintln!("Failed to delete {:?}: {}", path, e);
                    } else {
                        deleted_count += 1;
                    }
                    continue;
                }
            }

            // If not a test folder, apply the age threshold for empty rooms
            let metadata = fs::metadata(&path).expect("Failed to get metadata");
            let modified = metadata.modified().unwrap_or_else(|_| SystemTime::now());
            if modified < threshold {
                let mut has_videos = false;
                if let Ok(room_entries) = fs::read_dir(&path) {
                    for room_entry in room_entries.flatten() {
                        let file_path = room_entry.path();
                        if let Some(ext) = file_path.extension() {
                            if ext == "webm" || ext == "mp4" {
                                // Ignore test.webm already handled above
                                has_videos = true;
                                break;
                            }
                        }
                    }
                }
                if !has_videos {
                    println!("Deleting old empty room: {:?}", path);
                    if let Err(e) = fs::remove_dir_all(&path) {
                        eprintln!("Failed to delete {:?}: {}", path, e);
                    } else {
                        deleted_count += 1;
                    }
                }
            }
        }
    }


    println!("Cleanup complete! Deleted {} old empty rooms.", deleted_count);
}
