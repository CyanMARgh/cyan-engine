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
	format, chanels_type, data_type : GLenum;
	samples : u8; // 0 means no multisampling
	category : GLenum;
}
Sampling_Options :: struct {
	min_filter, mag_filter : GLenum;
}

Texture :: struct {
	id : u32;
	width, height : s32;
	using storage_format : Texture_Storage_Format; // TODO move to Texture_Base
}

make_texture_buffer :: (width : s32, height : s32, using storage_format : Texture_Storage_Format) -> Texture {
	if samples {
		return make_texture_multisample(width, height, storage_format);
	} else {
		return make_texture(width, height, storage_format, null, .[
			// GL_TEXTURE_MIN_FILTER, GL_NEAREST,
			// GL_TEXTURE_MAG_FILTER, GL_NEAREST
			GL_TEXTURE_WRAP_S, xx GL_CLAMP_TO_EDGE,
			GL_TEXTURE_WRAP_T, xx GL_CLAMP_TO_EDGE,
			GL_TEXTURE_MIN_FILTER, GL_LINEAR,
			GL_TEXTURE_MAG_FILTER, GL_LINEAR
		], false);
	}
}

make_texture :: (
	_width : s32, _height : s32,
	_storage_format : Texture_Storage_Format,

	src : *u8,

	params : []GLenum, 
	mipmap : bool
) -> Texture {
	using result := Texture.{width = _width, height = _height, storage_format = _storage_format};
	result.category = GL_TEXTURE_2D;

	glGenTextures(1, *result.id);
	glBindTexture(GL_TEXTURE_2D, result.id);
		for i : 0..params.count/2-1 {
			glTexParameteri(GL_TEXTURE_2D, xx params[i * 2], xx params[i * 2 + 1]);
		}
		glTexImage2D(GL_TEXTURE_2D, 0, xx format, xx width, xx height, 0, chanels_type, data_type, src);
		if mipmap glGenerateMipmap(GL_TEXTURE_2D);
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
	src_channels : GLenum;
	if layers == 1 {
		src_channels = GL_RED;
	} else if layers == 3 {
		src_channels = GL_RGB;
	} else if layers == 4 {
		src_channels = GL_RGBA;
	} else {
		assert(false, "unknown format\n");
	}
	interpolation :u32= GL_LINEAR; 
	// interpolation :u32= GL_LINEAR_MIPMAP_LINEAR;

	return make_texture(
		width, height, 
		.{format = src_channels, chanels_type = src_channels, data_type = GL_UNSIGNED_BYTE},
		image.bytes.data, 
		.[
			GL_TEXTURE_WRAP_S, xx GL_REPEAT,
			GL_TEXTURE_WRAP_T, xx GL_REPEAT,
			GL_TEXTURE_MIN_FILTER, interpolation,
			GL_TEXTURE_MAG_FILTER, interpolation
		], true
	), true;
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
bind_sampler :: (slot : u32, using texture : Texture) {
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
		.{format = GL_RGBA32F, chanels_type = GL_RGB, data_type = GL_FLOAT},
		xx source.data, .[
			GL_TEXTURE_MIN_FILTER, GL_NEAREST,
			GL_TEXTURE_MAG_FILTER, GL_NEAREST,
			GL_TEXTURE_WRAP_S, GL_REPEAT,
			GL_TEXTURE_WRAP_T, GL_REPEAT
		], false
	);
	array_free(source);
	return texture;
}