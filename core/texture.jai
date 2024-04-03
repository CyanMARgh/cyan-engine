Image :: struct {
	width, height, layers : s32;

	bytecount : int;
	pixels : *u32;
	#place bytecount;
	bytes : []u8;
}
at :: (using image : Image, x : s32, y : s32) -> u32 {
	return pixels[x + y * width];
}
load_image :: (path : string, expected_layers :u8= 3) -> Image {
	using image : Image;
	actual_source_layers : s32;
	pixels = xx stbi_load(temp_c_string(path), *width, *height, *actual_source_layers, expected_layers);
	layers = expected_layers;
	bytecount = width * height * layers;
	return image;
}
deinit :: (using image : *Image) {
	stbi_image_free(xx pixels);
}

// TODO for now storage_format.category ignored when passed as argument
Texture_Storage_Format :: struct {
	format : GLenum;
	samples : u8; // 0 means no multisampling
	category : GLenum;
}
Sampling_Options :: struct {
	min_filter, mag_filter : GLenum;
}

Texture :: struct {
	using storage_format : Texture_Storage_Format;
	id : u32;
	width, height, depth : s32 = 1;
}

make_texture_buffer :: (width : s32, height : s32, using storage_format : Texture_Storage_Format) -> Texture {
	if samples {
		return make_texture_multisample(width, height, storage_format);
	} else {
		return make_texture(width, height, storage_format, .[
			// GL_TEXTURE_MIN_FILTER, GL_NEAREST,
			// GL_TEXTURE_MAG_FILTER, GL_NEAREST
			GL_TEXTURE_WRAP_S, xx GL_CLAMP_TO_EDGE,
			GL_TEXTURE_WRAP_T, xx GL_CLAMP_TO_EDGE,
			GL_TEXTURE_MIN_FILTER, GL_LINEAR,
			GL_TEXTURE_MAG_FILTER, GL_LINEAR
		]);
	}
}

make_texture :: (
	_width : s32, _height : s32,
	_storage_format : Texture_Storage_Format,

	params : []GLenum
) -> Texture {
	using result := Texture.{width = _width, height = _height, storage_format = _storage_format};
	result.category = GL_TEXTURE_2D; // TODO maybe general

	glGenTextures(1, *result.id);
	glBindTexture(GL_TEXTURE_2D, result.id);
		for i : 0..params.count/2-1 {
			glTexParameteri(GL_TEXTURE_2D, xx params[i * 2], xx params[i * 2 + 1]);
		}
		glTexStorage2D(
			GL_TEXTURE_2D,
			1,
			xx format,
			xx width, xx height
		);
	glBindTexture(GL_TEXTURE_2D, 0);

	return result;
}
deinit :: (texture : *Texture) {
	glDeleteTextures(1, *texture.id);
	texture.id = 0;
}
make_texture_multisample :: (
	_width : s32, _height : s32,
	_storage_format : Texture_Storage_Format
) -> Texture {
	using result := Texture.{width = _width, height = _height, storage_format = _storage_format};
	category = GL_TEXTURE_2D_MULTISAMPLE;

	glGenTextures(1, *id);
	glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, id);
	// print("glTexImage2DMultisample\n");
	glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, samples, format, xx width, xx height, GL_TRUE);
	glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0);

	return result;
}
load_texture_from_image :: (
	using image : Image, 
	mag_filter :u32=GL_NEAREST,
	min_filter :u32=GL_NEAREST,
	wrap_s :u32=GL_REPEAT,
	wrap_t :u32=GL_REPEAT
) -> Texture, ok:bool {
	if !image.pixels return .{}, false;
	format, src_channels : GLenum;
	if layers == 1 {
		format = GL_R8;
		src_channels = GL_RED;
	} else if layers == 3 {
		format = GL_RGB8;
		src_channels = GL_RGB;
	} else if layers == 4 {
		format = GL_RGBA8;
		src_channels = GL_RGBA;
	} else {
		assert(false, "unknown format\n");
	}
	interpolation :u32= GL_LINEAR; 
	// interpolation :u32= GL_LINEAR_MIPMAP_LINEAR;

	texture := make_texture(
		width, height, 
		.{format = format},
		.[
			GL_TEXTURE_WRAP_S, xx GL_REPEAT,
			GL_TEXTURE_WRAP_T, xx GL_REPEAT,
			GL_TEXTURE_MIN_FILTER, interpolation,
			GL_TEXTURE_MAG_FILTER, interpolation
		]
	);
	glBindTexture(texture.category, texture.id);
		glTexSubImage2D(texture.category, 0, 0, 0, xx width, xx height, src_channels, GL_UNSIGNED_BYTE, pixels);
		glGenerateMipmap(texture.category);
	glBindTexture(texture.category, 0);

	return texture, true;
}
load_texture_from_file :: (
	path : string, expected_layers :u8= 4,
	mag_filter :u32=GL_NEAREST,
	min_filter :u32=GL_NEAREST,
	wrap_s :u32=GL_REPEAT,
	wrap_t :u32=GL_REPEAT
) -> Texture, ok:bool {
	image : Image;
	image = load_image(path, expected_layers);
	defer deinit(*image);
	texture : Texture;
	ok : bool;
	check_gl_error();
	texture, ok = load_texture_from_image(image);
	check_gl_error();
	return texture, ok;
}
bind :: (slot : u32, using texture : Texture) {
	glActiveTexture(GL_TEXTURE0 + slot);
	glBindTexture(category, id);
}
Sampler :: struct {
	id : u32;
}
make_test_sampler :: () -> Sampler {
	using sampler : Sampler;
	
	glGenSamplers(1, *id);
	glSamplerParameteri(id, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glSamplerParameteri(id, GL_TEXTURE_WRAP_T, GL_REPEAT);
	glSamplerParameteri(id, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glSamplerParameteri(id, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glSamplerParameterf(id, GL_TEXTURE_MAX_ANISOTROPY_EXT, 16.);	

	return sampler;
}
deinit :: (using sampler : *Sampler) {
	glDeleteSamplers(1, *id);
}

make_noise_texture :: (width : s32, height : s32) -> Texture {
	source := NewArray(width * height * 3, float);
	for * source it.* = random_get_within_range(-1, 1);
	texture := make_texture(
		width, height, 
		.{format = GL_RGBA32F}, .[
			GL_TEXTURE_MIN_FILTER, GL_NEAREST,
			GL_TEXTURE_MAG_FILTER, GL_NEAREST,
			GL_TEXTURE_WRAP_S, GL_REPEAT,
			GL_TEXTURE_WRAP_T, GL_REPEAT
		]
	);
	glBindTexture(texture.category, texture.id);
		glTexSubImage2D(texture.category, 0, 0, 0, xx width, xx height, GL_RGB, GL_FLOAT, source.data);
		glGenerateMipmap(texture.category);
	glBindTexture(texture.category, 0);
	array_free(source);
	return texture;
}

make_empty_texture_3d :: (_format : GLenum, size : u32) -> Texture {
	using result : Texture;
	width, height, depth = xx size;

	category = GL_TEXTURE_3D;
	format = _format;

	glGenTextures(1, *id);
	glBindTexture(category, id);
		glTexStorage3D(
			category,
			1,
			xx format,
			xx width, xx height, xx depth
		);
		glTexParameteri(category, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(category, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(category, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(category, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(category, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
	glBindTexture(category, 0);

	check_gl_error();

	return result;
}

make_stencil_texture :: (W : s32,  H : s32) -> Texture {
	using result : Texture;
	width, height, depth = W, H, 1;

	category = GL_TEXTURE_2D;

	glGenTextures(1, *id);
	glBindTexture(category, id);
		glTexImage2D(
			GL_TEXTURE_2D, 0, GL_DEPTH24_STENCIL8, xx W, xx H, 0, 
			GL_DEPTH_STENCIL, GL_UNSIGNED_INT_24_8, null
		);

		glTexParameteri(category, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(category, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(category, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(category, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glBindTexture(category, 0);

	check_gl_error();

	return result;
}

read_texture :: (using texture : Texture, channels : GLenum, data_type : GLenum) -> []u8 {
	size := 0;
	if channels == {
		case GL_RGBA; size = 4;
		case GL_RGB;  size = 3;
		case GL_RED;  size = 1;
		case; size = 0;
	}
	if data_type == {
		case GL_FLOAT; size *= size_of(float);
		case; size = 0;
	}

	assert(size != 0);
	result := NewArray(width * height * depth * size, u8);
	glBindTexture(category, id);
		glGetTexImage(category, 0, channels, data_type, result.data);
	glBindTexture(category, 0);
	return result;
}

