Texture_3D :: struct {
	id : u32;
	width, height, depth : s32;
	format : GLenum;
	category : GLenum;
}
make_texture_2d_array :: (_width : s32, _height : s32, layers : s32, src : *u8) -> Texture_3D {
	using result := Texture_3D.{width = _width, height = _height, depth = layers};
	category = GL_TEXTURE_2D_ARRAY;

	glGenTextures(1, *id);
	glBindTexture(category, id);
		glTexParameteri(category, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(category, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(category, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);

		glTexParameteri(category, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(category, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
		glTexImage3D(category, 0, GL_RED, xx width, xx height, xx depth, 0, GL_RED, GL_UNSIGNED_BYTE, src);
	glBindTexture(category, 0);
	return result;
}

deinit :: (using texture_3d : *Texture_3D) {
	glDeleteTextures(1, *id);
	id = 0;
}
bind_sampler :: (slot : u32, using texture : Texture_3D) {
	glActiveTexture(GL_TEXTURE0 + slot);
	glBindTexture(category, id);
}
