use std::fs;
use std::path::Path;

fn main() {
    let recordings_dir = Path::new("recordings");

    if !recordings_dir.exists() {
        println!("No recordings directory found.");
        return;
    }

    let mut room_count = 0;
    let mut total_size_bytes: u64 = 0;
    let mut video_count = 0;

    for entry in fs::read_dir(recordings_dir).expect("Failed to read recordings dir") {
        let entry = entry.expect("Failed to read entry");
        let path = entry.path();

        if path.is_dir() {
            room_count += 1;
            
            if let Ok(room_entries) = fs::read_dir(&path) {
                for room_entry in room_entries.flatten() {
                    let file_path = room_entry.path();
                    if file_path.is_file() {
                        if let Some(file_name) = file_path.file_name() {
                            if file_name == "test.webm" {
                                continue;
                            }
                        }
                        if let Some(ext) = file_path.extension() {
                            if ext == "webm" || ext == "mp4" {
                                video_count += 1;
                                if let Ok(metadata) = fs::metadata(&file_path) {
                                    total_size_bytes += metadata.len();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    let mb = total_size_bytes as f64 / (1024.0 * 1024.0);

    println!("--- WTFONE Storage Stats ---");
    println!("Total Rooms:  {}", room_count);
    println!("Total Videos: {}", video_count);
    println!("Total Size:   {:.2} MB", mb);
    println!("----------------------------");
}
