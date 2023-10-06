Framebuffer :: struct {
	fbo : u32;

	width, height : s32 = -1, -1;
	samples :u8= 0;

	MAX_ATTACHMENTS :: 4;
	has_depth_attachment := false;
	attachments_count := 0;
	color_attachments_count := 0;
	textures : [MAX_ATTACHMENTS]Texture;
	attachments : [MAX_ATTACHMENTS]FB_Attachment;
	// TODO keep only name and attachment_type, store rest in texture and make Texture_Properties struct
}
FB_Attachment :: struct {
	name : string;
	attachment_type : enum u8 { NONE; DEPTH; COLOR; } = .NONE;
	format, chanels_type, data_type : GLenum;
}
srcheader :: (using framebuffer : Framebuffer) -> string {
	builder := String_Builder.{allocator = temp};
	if samples {
		print_to_builder(*builder, "#define SAMPLES %\n", samples);
		for 0..attachments_count-1 {
			using att := attachments[it];
			print_to_builder(*builder, "#define U_SAMPLER2DMS_%\n", uppercase(name));
			print_to_builder(*builder, "layout(binding = %) uniform sampler2D u_%;\n", it, name);
		}
	} else {
		for 0..attachments_count-1 {
			using att := attachments[it];
			print_to_builder(*builder, "#define U_SAMPLER2D_%;\n", uppercase(name));
			print_to_builder(*builder, "layout(binding = %) uniform sampler2D u_%;\n", it, name);
		}
	}
	return builder_to_string(*builder, allocator = temp);
}
channels_type_to_name :: (chanels_type : GLenum) -> string {
	result := "";
	if chanels_type == {
		case GL_RGBA; result = "vec4";
		case GL_RGB; result = "vec3";
		case GL_DEPTH_COMPONENT; result = "float";
	}
	assert(result != "");
	return result;
}

dstheader :: (using framebuffer : Framebuffer) -> string {
	builder := String_Builder.{allocator = temp};
	color_attachment := 0;
	for 0..attachments_count-1 {
		using att := attachments[it];
		if attachment_type != .COLOR continue;
		print_to_builder(*builder, "#define O_%\n", uppercase(name));
		print_to_builder(*builder, "layout(location = %) out % o_%;\n", color_attachment, channels_type_to_name(chanels_type), name);
		color_attachment += 1;
	}
	return builder_to_string(*builder, allocator = temp);
}

make_framebuffer :: (size : ivec2, _attachments : ..FB_Attachment, samples :u8= 0) -> Framebuffer, ok:bool {
	fb, ok := make_framebuffer(size.x, size.y, .._attachments, samples);
	return fb, ok;
}


make_framebuffer :: (_width : s32, _height : s32, _attachments : ..FB_Attachment, samples :u8= 0) -> Framebuffer, ok:bool {
	using,except(samples) framebuffer := Framebuffer.{width = _width, height = _height, samples = samples};

	add_attachment :: (fba : FB_Attachment) #expand {
		gl_attachment_type : GLenum;
		if fba.attachment_type == .NONE {
			return;
		} else if fba.attachment_type == .DEPTH {
			assert(!has_depth_attachment);
			gl_attachment_type = GL_DEPTH_ATTACHMENT;
			has_depth_attachment = true;
		} else {
			gl_attachment_type = xx (GL_COLOR_ATTACHMENT0 + color_attachments_count);
			color_attachments_count += 1;			
		}
		// print("+ attachment\n");
		texture := make_texture_buffer(width, height, .{fba.format, fba.chanels_type, fba.data_type, samples, 0});
		glFramebufferTexture2D(GL_FRAMEBUFFER, gl_attachment_type, texture.category, texture.id, 0);
		textures[attachments_count] = texture;
		attachments[attachments_count] = fba;
		attachments_count += 1;
	}

	glGenFramebuffers(1, *fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		for _attachments {
			add_attachment(it);
		}

		error := glCheckFramebufferStatus(GL_FRAMEBUFFER);
		if error != GL_FRAMEBUFFER_COMPLETE {
			deinit(*framebuffer);
			print("ERROR: Framebuffer is not complete (error = %)!\n", error);
			return .{}, false;
		}
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	return framebuffer, true;
}
deinit :: (using framebuffer : *Framebuffer) {
	for * textures deinit(it);
	glDeleteFramebuffers(1, *fbo);	
}
bind_as_target :: (using framebuffer : Framebuffer) {
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glViewport(0, 0, xx width, xx height);
	buffers : [8]u32;
	for * buffers it.* = xx (it_index + GL_COLOR_ATTACHMENT0);
	glDrawBuffers(xx color_attachments_count, buffers.data);
}
bind_default_traget :: () {
	using backend_state.window_metrics;
	glViewport(0, 0, xx width, xx height);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
}
bind_as_source :: (using framebuffer : Framebuffer) {
	for i : 0..attachments_count-1 {
		bind_sampler(xx i, textures[i]);
	}
}
set_size :: (using framebuffer : *Framebuffer, size : ivec2) -> ok:bool {
	ok := true;
	if width != size.x || height != size.y {
		deinit(framebuffer);
		width, height = size.x, size.y;
		framebuffer.*, ok = make_framebuffer(width, height, ..attachments, samples);
	}
	return ok;
}