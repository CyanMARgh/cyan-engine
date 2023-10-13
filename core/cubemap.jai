Cubemap :: struct {
	id : u32;
	width, height : s32 = -1, -1;
	category : GLenum = GL_TEXTURE_CUBE_MAP;	
}

load_cubemap_from_file :: (path_prefix : string, paths : ..string) -> Cubemap, ok:bool {
	using result := Cubemap.{};
	glGenTextures(1, *id);
	glBindTexture(GL_TEXTURE_CUBE_MAP, id);

	for i : 0..5 {
		img := load_image(tprint("%1%2", path_prefix, paths[i]));
		defer deinit(*img);
		if width == -1 {
			width, height = img.width, img.height;
		} else {
			if width != img.width || height != img.height {
				deinit(*result);
				return .{}, false;
			}
		}

		glTexImage2D(
			xx(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i), 
			0, GL_RGB, xx width, xx height, 0, GL_RGB, GL_UNSIGNED_BYTE, img.pixels
        );
	}

	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

	glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
	return result, true;
}
make_cubemap :: (_width : s32, _height : s32, mipmap := false) -> Cubemap {
	using result := Cubemap.{width = _width, height = _height};
	glGenTextures(1, *id);
	glBindTexture(GL_TEXTURE_CUBE_MAP, id);

	for i : 0..5 {
		glTexImage2D(
			xx(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i), 
			0, GL_RGB, xx width, xx height, 0, GL_RGB, GL_UNSIGNED_BYTE, null
        );
	}

	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, xx ifx mipmap then GL_LINEAR_MIPMAP_LINEAR else GL_LINEAR);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

	if mipmap glGenerateMipmap(GL_TEXTURE_CUBE_MAP);

	glBindTexture(GL_TEXTURE_CUBE_MAP, 0);
	return result;
}

deinit :: (using cubemap : *Cubemap) {
	glDeleteTextures(1, *id);
	id = 0;
	width, height = -1;
}

//TODO rename to "bind_as_source"
bind_sampler :: (slot : u32, using cubemap : Cubemap) {
	glActiveTexture(GL_TEXTURE0 + slot);
	glBindTexture(category, id);
} 