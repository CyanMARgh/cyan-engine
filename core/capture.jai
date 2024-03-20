#import "Process";
#import "Basic";
#import "File";
#import "stb_image_resize";

#if OS == .WINDOWS {
	#import "Windows";
} else {
	#import "POSIX";
}

FFMPEG :: struct {
	process : Process;
	buffer : Frame;
}
ffmpeg_start_rendering :: (width : int, height : int, fps := 60, filename := "output.mp4", path := ".", bitrate := 2500) -> FFMPEG, ok:bool {
	ffmpeg := FFMPEG.{
		buffer = make_frame(width, height)
	};

	make_directory_if_it_does_not_exist(path, true);
	success := create_process(*ffmpeg.process,
		"ffmpeg",
		"-loglevel", "verbose",
		"-y",
		"-f", "rawvideo",
		"-pix_fmt", "rgba",
		"-s", tprint("%x%", width, height),
		"-r", tprint("%", fps),
		"-i", "-",
		"-c:v", "libx264",
		"-vb", tprint("%k", bitrate),
		"-c:a", "aac",
		"-ab", "200k",
		"-pix_fmt", "yuv420p",
		tprint("%/%", path, filename),
		capture_and_return_output = true
	);
	return ffmpeg, success;
}
ffmpeg_end_rendering :: (ffmpeg : *FFMPEG) {
	#if OS == .WINDOWS {
		// fclose(ffmpeg.process.input.handle); //not sure about this
	} else {
		close(ffmpeg.process.input.handle);
	}
	success, result := get_process_result(*ffmpeg.process);
	clear(ffmpeg.buffer);
}
ffmpeg_send_frame :: (ffmpeg : *FFMPEG) {
	ffmpeg_send_frame_helper(ffmpeg, ffmpeg.buffer);
}
ffmpeg_scale_and_send_frame :: (ffmpeg : *FFMPEG, input_frame : Frame) -> ok:bool {
	resized := input_frame;
	// print("(3)\n");
	if ffmpeg.buffer.width != input_frame.width && ffmpeg.buffer.height != input_frame.height {		
		stbir_resize_uint8(
			xx input_frame.bytes, xx input_frame.width, xx input_frame.height, xx(input_frame.width * 4),
			xx ffmpeg.buffer.bytes, xx ffmpeg.buffer.width, xx ffmpeg.buffer.height, xx(ffmpeg.buffer.width * 4),
			4
		);
		resized = ffmpeg.buffer;
	}
	// print("(4)\n");
	ffmpeg_send_frame_helper(ffmpeg, resized);
	return true;
}

ffmpeg_send_frame_helper :: (ffmpeg : *FFMPEG, frame : Frame) {
	bytes : []u8;
	bytes.data = frame.bytes;
	bytes.count = frame.bytecount;
	// print("(5)\n");
	total_wriiten := 0;
	while bytes.count > 0 {
		// print("(6): __ / % / %\n", total_wriiten, frame.bytecount);
		succes, bytes_written := write_to_process(*ffmpeg.process, bytes);
		total_wriiten += bytes_written;
		// print("(7): % / % / %\n", bytes_written, total_wriiten, frame.bytecount);
		bytes.data += bytes_written;
		bytes.count -= bytes_written;
	}
	// print("(8)\n");
}

Frame :: struct {
	width, height : int;
	bytecount : int;
	bytes : *u8;
}
make_frame :: (width : int, height : int) -> Frame {
	return .{
		width = width,
		height = height,
		bytecount = width * height * 4,
		bytes = alloc(width * height * 4)
	};
}
clear :: (using frame : Frame) {
	free(bytes);
}
fill_frame_with_screenshot :: (buffer : *Frame) {
	using backend_state;
	width, height := window_metrics.width, window_metrics.height;
	assert(width * height < 1920 * 1080);

	buffer.width, buffer.height = width, height;
	buffer.bytecount = width * height * 4;

	glReadPixels(0, 0, xx width, xx height, GL_RGBA, GL_UNSIGNED_BYTE, xx buffer.bytes);
	flip_and_remove_transparency(buffer);
}

flip_and_remove_transparency :: (using frame : *Frame) {
	for y1 : 0..(height / 2 - 1) {
		y2 := height - y1 - 1;
		row1 := cast(*u32)bytes + y1 * width;
		row2 := cast(*u32)bytes + y2 * width;
		for x : 0..width-1 {
			row1[x], row2[x] = row2[x], row1[x];
		}
	}
	ptr_32 := cast(*u32)bytes;
	for i : 0..height*width-1 {
		ptr_32[i] |= 0xFF000000;
	}
}
