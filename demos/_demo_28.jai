#import "Basic";
#import "stb_image";
#import "stb_image_write";
#import "Math";

main :: () {
	W, H, channels : s32;
	cbuf := cast(*u32)stbi_load("res/C1W.png", *W, *H, *channels, 4);
	defer stbi_image_free(cbuf);

	DW, DH, Dchannels : s32;
	hbuf := cast(*u8)stbi_load("res/D1.png", *DW, *DH, *Dchannels, 1);
	assert(Dchannels == 1);
	// assert(DW * 2 == W && DH * 2 == H, "% % % %\n", W, H, DW, DH);


	TW, TH :: 400, 240;
	tbuf : [TW * TH]u32;
	ybuf : [TW]int;
	for * ybuf it.* = TH;

	// for y : 0..TH-1 {
	// 	for x : 0..TW-1 {
	// 		tbuf[y * TW + x] = cbuf[(y * H / TH) * W + (x * W / TW)];
	// 	}
	// }
	mmod :: (x : int, a : int) -> int {
		return (x % a) + (ifx x < 0 then a); 		
	}
	cbuf_at :: (x : int, y : int) -> u32 #expand {
		return cbuf[W * mmod(y, H) + mmod(x, W)];
	}
	hbuf_at :: (xnum : int, xdenum : int, y : int) -> s32 #expand {
		return hbuf[DW * (mmod(y * DH / H, DH)) + mmod((xnum * DW / xdenum) / W, DW)];
	}
	hibuf_at :: (xnum : int, xdenum : int, y : int) -> int #expand {
		x := xnum / xdenum;
		xf := mmod(xnum, xdenum);
		h1 := hbuf[DW * mmod(y * DH / H, DH) + mmod(x * DW / W, DW)];
		h2 := hbuf[DW * mmod(y * DH / H, DH) + mmod((x * DW / W) + 1, DW)];
		return (h1 * (xdenum - xf) + h2 * xf) / xdenum;
	}

	owerdraw := 0;
	draw_vertical_line :: (x : int, h : int, color : u32) #expand {
		h = max(0, h);
		if h < ybuf[x] {
			for y : h..ybuf[x]-1 {
				// print("--> % %\n", x, y);
				tbuf[y * TW + x] = color;
				owerdraw += 1;
			}
			ybuf[x] = h;
		}
	}
	bilog :: (x : int) -> int {
		assert(x > 0);
		i := 0;
		while x {
			x >>= 1;
			i += 1;
		}
		return i;
	}
	render :: (p0x : int, p0y : int, height : int, horizon : int, scale_height : int, distance : int) #expand {
		// for z : 2..distance
		zi := 2;
		while 1 {
			far := 150;
			farfar := 200;
			// z := ifx zi < far then zi else ifx zi < farfar then (zi - far) * 2 + far else (zi - farfar) * 5 + farfar;
			z := zi;
			if z > distance break;
			zi += 1;
			plx := -z + p0x;
			prx :=  z + p0x;
			py  := -z + p0y;

			// dx = (prx - plx) / screen_width;
			for i : 0..TW-1 {
				pxnum := ((prx - plx) * i);
				pxdenum := TW;
				px := pxnum / pxdenum;
				// print("-> % %\n", px, py);
				// h := cast(s32)hbuf_at(px, py);
				h := hibuf_at(pxnum, pxdenum, py);
				hos := ((height - h) * scale_height) / z + horizon;
				color := cbuf_at(px, py);
				draw_vertical_line(i, hos, color);
			}
		}
	}
	render(512, 200, 120, 120, 120, 500);
	for h, x : ybuf {
		for y : 0..h-1 {
			tbuf[y * TW + x] = 0xffe6ccb3;
		}
	}
	print("owerdraw: %, %\%", owerdraw, owerdraw * 100 / TW / TH);


// def Render(p, height, horizon, scale_height, distance, screen_width, screen_height):
//     # Draw from back to the front (high z coordinate to low z coordinate)
//     for z in range(distance, 1, -1):
//         # Find line on map. This calculation corresponds to a field of view of 90°
//         pleft  = Point(-z + p.x, -z + p.y)
//         pright = Point( z + p.x, -z + p.y)
//         # segment the line
//         dx = (pright.x - pleft.x) / screen_width
//         # Raster line and draw a vertical line for each segment
//         for i in range(0, screen_width):
//             height_on_screen = (height - heightmap[pleft.x, pleft.y]) / z * scale_height. + horizon
//             DrawVerticalLine(i, height_on_screen, screen_height, colormap[pleft.x, pleft.y])
//             pleft.x += dx

// # Call the render function with the camera parameters:
// # position, height, horizon line position,
// # scaling factor for the height, the largest distance, 
// # screen width and the screen height parameter
// Render( Point(0, 0), 50, 120, 120, 300, 800, 600 )

	stbi_write_png("out_new.png", TW, TH, 4, tbuf.data, TW * 4);
}