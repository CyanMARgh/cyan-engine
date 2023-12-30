from_c_string :: (c_str : *[$N]s8) -> string {
	str : string;
	str.data = cast(*u8) c_str;
	str.count = N;
	return str;
}
FATAL_GL_ERROR_CHECK :: false;
check_gl_error :: (loc := #caller_location) {
	has_errors := false;
	while true {
		err := glGetError();
		if !err break;
		has_errors = true;
		path := parse_path(loc.fully_pathed_filename).words;
		print_color("error at line %, %. code = %\n", loc.line_number, path[path.count-1], err, color = .RED);
	}
	#if FATAL_GL_ERROR_CHECK if has_errors exit(1);
}

Check_Time :: struct { loc : Source_Code_Location; }
check_time :: (cl := #caller_location) -> Check_Time { return .{cl}; }

for_expansion :: (_check_time : Check_Time, $body : Code, flags : For_Flags) #expand {
	t0 := current_time_monotonic();
	`it, `it_index := 0;
	#insert body;
	t1 := current_time_monotonic();
	print("time = %, loc = %\n", to_float64_seconds(t1 - t0), _check_time.loc);
}

log10 :: (x : int) -> int {
	x = abs(x);
	count := 1;
	while x > 9 {
		x /= 10;
		count += 1;
	}
	return count;
}

tmap :: (array: [] $T, f: (T) -> $S) -> [] S {
	results := NewArray(array.count, S, allocator = temp);
	for array results[it_index] = f(it);
	return results;
}

tjoin :: (first : []$T, other : ..Any) -> []T {
	result : [..]T;
	result.allocator = temp;
	array_add(*result, ..first);
	for other {
		if it.type == type_info(T) {
			array_add(*result, (cast(*T)it.value_pointer).*);
		} else if it.type == type_info([]T) {
			array_add(*result, ..(cast(*[]T)it.value_pointer).*);
		} else {
			assert(false);
		}
		assert(it.type == type_info(T) || it.type == type_info([]T));
	}
}

uppercase :: (src : string) -> string {
	res := copy_string(src,, allocator = temp);
	for *c : cast([]u8)res {
		if c.* >= #char"a" && c.* <= #char"z" {
			c.* = xx (c.* + #char"A" - #char"a");
		}
	}
	return res;
}

hex2f3 :: (code : u32) -> Vector3 {
	b := code & 0xFF;
	g := (code >> 8) & 0xFF;
	r := (code >> 16) & 0xFF;
	return .{xx r, xx g, xx b} / 255.;
}
hex2f4 :: (code : u32) -> Vector4 {
	b := code & 0xFF;
	g := (code >> 8) & 0xFF;
	r := (code >> 16) & 0xFF;
	return .{xx r, xx g, xx b, 255.} / 255.;
}

align_of :: ($T : Type) -> int {
	o : struct { b : bool; t : T; }
	return xx(cast(u64) *o.t - cast(u64) *o.b);
}

Rect :: struct {
	left_top : Vector2;
	right_bottom : Vector2;
	#place left_top;
	left, top, right, bottom : float;
}
add_gap :: (using r : Rect, gap : float) -> Rect {
	return .{.{left + gap, top + gap}, .{right - gap, bottom - gap}};
}
inside :: (position : Vector2, zone : Rect) -> bool {
	return 
		zone.left_top.x <= position.x && position.x <= zone.right_bottom.x &&
		zone.left_top.y <= position.y && position.y <= zone.right_bottom.y;
}

scl_hash :: (using loc : Source_Code_Location) -> u32 {
	h123 : [2]int = int.[line_number, character_number];
	return get_hash(h123);
}
scl_cmp :: (loc_1 : Source_Code_Location, loc_2 : Source_Code_Location) -> bool {
	if loc_1.line_number != loc_2.line_number return false;
	if loc_1.character_number != loc_2.character_number return false;
	return loc_1.fully_pathed_filename == loc_2.fully_pathed_filename;
}
