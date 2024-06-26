#import,dir "../core";
#import "Basic"()(MEMORY_DEBUGGER = true);
#import "Math";
#import "GL";
#import "Random";
#import "stb_image";
#import "File";

patterns_gradient :: u8.[
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x88, 0x00, 0x00, 0x00, 0x88, 0x00, 0x00, 0x00,
	0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00,
	0xaa, 0x00, 0x22, 0x00, 0xaa, 0x00, 0x22, 0x00,
	0xaa, 0x00, 0xaa, 0x00, 0xaa, 0x00, 0xaa, 0x00,
	0xaa, 0x44, 0xaa, 0x11, 0xaa, 0x44, 0xaa, 0x11,
	0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55,
	0xaa, 0xdd, 0xaa, 0x77, 0xaa, 0xdd, 0xaa, 0x77,
	0xaa, 0xff, 0xaa, 0xff, 0xaa, 0xff, 0xaa, 0xff,
	0xaa, 0xff, 0xee, 0xff, 0xaa, 0xff, 0xee, 0xff,
	0xbb, 0xff, 0xee, 0xff, 0xbb, 0xff, 0xee, 0xff,
	0xff, 0xff, 0xee, 0xff, 0xff, 0xff, 0xee, 0xff,
	0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
];

brightness :: (v : u32) -> u8 {
	f :=
		((v & 0x00ff0000) >> 16) * 0.212655 +
		((v & 0x0000ff00) >>  8) * 0.715158 +
		((v & 0x000000ff) >>  0) * 0.072187;

	f /= 255.;

	return xx (clamp(cast(int)((f * 2 - 0.16) * 13), 0, 12));
}

brightness_clamp :: (v : u32) -> u32 {
	f :=
		((v & 0x00ff0000) >> 16) * 0.212655 +
		((v & 0x0000ff00) >>  8) * 0.715158 +
		((v & 0x000000ff) >>  0) * 0.072187;

	return xx ifx f < 128. then 0xff000000 else 0xffffffff;
}

gray :: (v : u32) -> u32 {
	f :=
		((v & 0x00ff0000) >> 16) * 0.212655 +
		((v & 0x0000ff00) >>  8) * 0.715158 +
		((v & 0x000000ff) >>  0) * 0.072187;

	p := cast(u32)clamp(cast(int)(f * 2 - 40.), 0, 255);
	return 0xff000000 | (p << 16) | (p << 8) | p;
	// v &= 0xff000000;
	// return v;
}

ID :: 2;
S :: 16;

main :: () {
	defer report_memory_leaks();
	init_resources(); defer deinit_resources();
	init_default_graphics(); defer deinit_default_graphics();

	shader_show_texture := compile_shader_vf(VERT_SCREEN_SPACE, FRAG_SHOW_TEXTURE);
	defer deinit(*shader_show_texture);

	CW, CH, Cchannels : s32;

	cbuf := cast(*u32)stbi_load(tprint("res/C%_%.png\0", ID, S).data, *CW, *CH, *Cchannels, 4);

	cbuf_processed := NewArray(CW * CH / 2, u8);
	defer array_free(cbuf_processed);

	for i : 0..CW * CH / 2 - 1 {
		cbuf_processed[i] = brightness(cbuf[i * 2]) | (brightness(cbuf[i * 2 + 1]) << 4);
	}
	write_entire_file(tprint("res/C%_%.bin\0", ID, S), cast(string)cbuf_processed);
	stbi_image_free(cbuf);


	// assert(Dchannels == 4);

	DW, DH, Dchannels : s32;
	hbuf := cast(*u8)stbi_load(tprint("res/D%_%.png\0", ID, S).data, *DW, *DH, *Dchannels, 4);
	// assert(Dchannels == 1);
	assert(CH == DH && CW == DW, "%, %, %, %, (%)\n", CH, DH, CW, DW, tprint("res/D%_%.png\0", ID, S));

	hbuf_processed := NewArray(DW * DH, u8);
	defer array_free(hbuf_processed);
	for i : 0..DW * DH - 1 {
		hbuf_processed[i] = hbuf[i * 4];
	}
	write_entire_file(tprint("res/D%_%.bin\0", ID, S), cast(string)hbuf_processed);
	stbi_image_free(hbuf);
	
	TW, TH :: 400, 240;
	BM_STRIDE :: 52;
	texture_data_u8 : [BM_STRIDE * TH]u8;
	texture_data : [TW * TH]u32;
	ybuf : [TW]int;

	mmod :: (x : int, a : int) -> int {
		x %= a;
		return ifx x < 0 then x + a else x; 		
	}
	cbuf_at :: (x : int, y : int) -> u8 #expand {
		x /= 2048 / S;
		y /= 2048 / S;
		i := CW * mmod(y, CH) + mmod(x, CW);
		assert(i >= 0 && i < CW * CH);
		// return cbuf[i];
		return (cbuf_processed[i >> 1] >> ((i & 1) << 2)) & 0xf;
	}
	hbuf_at :: (x : int, y : int) -> s32 #expand {
		x /= 2048 / S;
		y /= 2048 / S;
		i := (CW * mmod(y, CH) + mmod(x, CW));
		assert(i >= 0 && i < DW * DH, "x, y: %, % -> %\n", mmod(x, CW), y, mmod(y, CH));
		return hbuf_processed[i];
	}
	// hibuf_at :: (xnum : int, xdenum : int, y : int) -> int #expand {
	// 	x := xnum / xdenum;
	// 	xf := mmod(xnum, xdenum);
	// 	h1 := hbuf[4 * (DW * mmod(y * DH / CH, DH) + mmod(x * DW / CW, DW))];
	// 	h2 := hbuf[4 * (DW * mmod(y * DH / CH, DH) + mmod((x * DW / CW) + 1, DW))];
	// 	return (h1 * (xdenum - xf) + h2 * xf) / xdenum;
	// }

	pixels := 0;
	draw_vertical_line :: (x : int, _h : int, color : u8) #expand {
		h := max(0, _h);
		if h < ybuf[x] {
			for y : h..ybuf[x]-1 {
				byte := patterns_gradient[(y & 7) + color * 8];
				mask :u8= cast(u8)0x80 >> (x & 7);

				texture_data_u8[y * BM_STRIDE + x / 8] |= mask & byte;
				// texture_data[y * TW + x] = color;
				// pixels += 1;
			}
			ybuf[x] = h;
		}
	}

	render :: (p0x : int, p0y : int, height : int, horizon : int, scale_height : int, distance : int) #expand {
		for * ybuf it.* = TH;
		for * texture_data_u8 it.* = 0;
		for zi : 0..distance-1 {
			z := zi * 6 + 200;
			h1 :: 300;
			h2 :: 500;
			if(z > h1) {
				z = (z - h1) * 3 / 2 + h1;
			}
			if(z > h2) {
				z = (z - h2) * 3 + h2;
			}
			// print("z = %\n", z);
			// z := ifx zi < h1 then 70 + zi else if zi < h2 then (zi - h1) * 3 + h1 else zi - ;
			plx := -z + p0x;
			prx :=  z + p0x;
			py  := -z + p0y;

			for i : 0..TW-1 {
				px := plx + ((prx - plx) * i) / TW;
				h := hbuf_at(px, py);
				hos := ((height - h) * scale_height) / z + horizon;
				color := cbuf_at(px, py);
				draw_vertical_line(i, hos, color);
			}
		}
		for x : 0..TW-1 draw_vertical_line(x, 0, 12);
	}

	conver_bw_to_rgb :: () #expand {
		for y : 0..TH-1 {
			for x : 0..TW-1 {
				texture_data[y * TW + x] = xx ifx (texture_data_u8[y * BM_STRIDE + x / 8] & (0x80 >> (x & 7))) then 0xffa6adaf else 0xff262d2f;
			}
		}
	}

	update_texture :: () #expand {
		render(`px, `py, 300, 120, 120, 50);


		// {
		// 	i := 0;
		// 	for y : 0..TH-1 {
		// 		for x : 0..TW-1 {
		// 			b := brightness(texture_data[i]);
		// 			byte := patterns_gradient[(y & 7) + b * 8];
		// 			mask := 0x80 >> (x & 7);
		// 			texture_data[i] = xx ifx mask & byte then 0xffffffff else 0xff000000; 
		// 			// texture_data[i] = gray(texture_data[i]);
		// 			i += 1;
		// 		}
		// 	}
		// }

		conver_bw_to_rgb();
		// for * texture_data it.* = brightness_clamp(it.*);
	}

	// tex_u8 : [416 * 240]u8;
	// texture_data_u8[0] = 0x80;

	// update_texture :: () #expand {
		// for y : 0..239 {
		// 	for x : 0..399 {
		// 		texture_data[y * 400 + x] = xx ifx (tex_u8[y * 52 + x / 8] & (0x80 >> (x & 7))) then 0xffffffff;
		// 	}
		// }
	// }

	texture := make_texture(TW, TH, .{GL_RGBA8, 0, GL_TEXTURE_2D}, .[
		GL_TEXTURE_WRAP_S, xx GL_CLAMP_TO_EDGE,
		GL_TEXTURE_WRAP_T, xx GL_CLAMP_TO_EDGE,
		GL_TEXTURE_MIN_FILTER, GL_NEAREST,
		GL_TEXTURE_MAG_FILTER, GL_NEAREST
	]);
	defer deinit(*texture);

	px, py := 0, 0;

	glEnable(GL_CULL_FACE);
	for window_cycle(capture_video = false, print_statistical_fps = true) {
		for Events if it.type == {
			case .KEY; using it.key_event;
			if type == .PRESS ifx keycode == {
				case GLFW_KEY_ESCAPE; exit();
				case #char"P"; screenshot();
			}
		}
		// px += 1;
		py -= 10;
		py %= 2048;
		glClearColor(.7, .8, .9, 1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

		update_texture();
		// print("%\n", pixels);
		bind(0, texture);
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, TW, TH, GL_RGBA, GL_UNSIGNED_BYTE, texture_data.data);

		for *shader_show_texture {			
			bind(0, texture);
			draw_empty_mesh(6);
		}
		check_gl_error();
	}
}

VERT_SCREEN_SPACE :: #string GLSL
	out vec2 uv;
	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 _uv = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		uv = vec2(_uv.x, 1 - _uv.y);
		gl_Position = vec4(_uv * 2 - 1, 0, 1);
	}
GLSL
FRAG_SHOW_TEXTURE :: #string GLSL
	layout(binding = 0) uniform sampler2D u_color;
	in vec2 uv;
	out vec4 o_color;
	void main() {
		o_color = texture(u_color, uv);
	}
GLSL