use std::path::PathBuf;
use std::process::Command;
use tokio::task;

pub fn spawn_grid_processing(room_id: String) {
    task::spawn(async move {
        tracing::info!("Waiting 5s for any pending uploads before merging grid for {}", room_id);
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        
        let dir = PathBuf::from("recordings").join(&room_id);
        if !dir.exists() {
            tracing::info!("No recordings dir found for room {}", room_id);
            return;
        }

        let mut files = Vec::new();
        if let Ok(mut entries) = tokio::fs::read_dir(&dir).await {
            while let Ok(Some(entry)) = entries.next_entry().await {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.ends_with(".webm") && !name.contains("grid_merged") {
                    // Extract timestamp
                    if let Some(ts_str) = name.split('_').next() {
                        if let Ok(ts) = ts_str.parse::<u64>() {
                            files.push((ts, entry.path()));
                        }
                    }
                }
            }
        }

        if files.is_empty() {
            return;
        }

        // Cap to 4 files for grid layout simplicity
        files.truncate(4);

        // Sort by timestamp
        files.sort_by_key(|f| f.0);
        let min_ts = files[0].0;

        let out_path = dir.join("grid_merged.webm");
        let mut cmd = Command::new("ffmpeg");
        cmd.arg("-y");

        let mut filter_complex = String::new();
        let mut video_outputs = Vec::new();
        let mut audio_outputs = Vec::new();

        for (i, (ts, path)) in files.iter().enumerate() {
            cmd.arg("-i");
            cmd.arg(path);

            let delay_ms = ts - min_ts;

            // Video filter: scale and pad start
            filter_complex.push_str(&format!(
                "[{}:v]scale=640:360,tpad=start_duration={}ms:color=black[v{}];",
                i, delay_ms, i
            ));
            video_outputs.push(format!("[v{}]", i));

            // Audio filter: delay
            filter_complex.push_str(&format!(
                "[{}:a]adelay={}ms:all=1[a{}];",
                i, delay_ms, i
            ));
            audio_outputs.push(format!("[a{}]", i));
        }

        let layout = match files.len() {
            1 => "0_0",
            2 => "0_0|w0_0",
            3 => "0_0|w0_0|0_h0",
            4 => "0_0|w0_0|0_h0|w0_h0",
            _ => "0_0"
        };

        let inputs_v = video_outputs.join("");
        filter_complex.push_str(&format!(
            "{}xstack=inputs={}:layout={}:fill=black[vout];",
            inputs_v, files.len(), layout
        ));

        let inputs_a = audio_outputs.join("");
        filter_complex.push_str(&format!(
            "{}amix=inputs={}:dropout_transition=0:normalize=0[aout]",
            inputs_a, files.len()
        ));

        cmd.arg("-filter_complex").arg(&filter_complex);
        cmd.arg("-map").arg("[vout]");
        cmd.arg("-map").arg("[aout]");
        cmd.arg(&out_path);

        tracing::info!("Running ffmpeg grid build for room {}: {:?}", room_id, cmd);

        if let Ok(output) = cmd.output() {
            if output.status.success() {
                tracing::info!("Smart grid merged successfully for room {}! Saved to {:?}", room_id, out_path);
            } else {
                let err = String::from_utf8_lossy(&output.stderr);
                tracing::error!("Grid merging failed for room {}: {}", room_id, err);
                
                // If it fails (maybe missing video/audio streams in some files), log a simpler warning.
                if err.contains("Stream specifier") {
                    tracing::error!("Stream missing in one of the files. Smart grid expects both video+audio tracks.");
                }
            }
        }
    });
}
