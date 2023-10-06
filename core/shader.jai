GLSL_VERSION_LINE :: #run tprint("\t#version %\n", GL_REQUIRED_VERSION_MAJOR * 100 + GL_REQUIRED_VERSION_MINOR * 10);

Shader_Part :: struct {
	id : u32;
}
Shader :: struct {
	id : u32;	
	extra_fields : Table(string, s32);
	// gsx, gsy, gsz : u32 = 8, 4, 1; // for compute shader only
}

incldefs :: (sources : ..string) -> string {
	builder := String_Builder.{allocator = temp};
	assert(sources.count >= 1);
	for i : 0..sources.count-2 {
		source := sources[i];
		for line : split(source, cast(u8)#char"\n") {
			print_to_builder(*builder, "\t/*+*/#define %\n", line);
		}
		append(*builder, "\n");
	}
	append(*builder, sources[sources.count - 1]);
	return builder_to_string(*builder, allocator = temp);	
}
defs :: (lines : ..string) -> string {
	builder := String_Builder.{allocator = temp};
	for lines {
		print_to_builder(*builder, "#define %\n", it);
	}
	return builder_to_string(*builder, allocator = temp);
}
incl :: (sources : ..string) -> string {
	builder := String_Builder.{allocator = temp};
	assert(sources.count >= 1);
	for i : 0..sources.count-2 {
		source := sources[i];
		for line : split(source, cast(u8)#char"\n") {
			print_to_builder(*builder, "\t/*+*/%\n", line);
		}
		append(*builder, "\n");
	}
	append(*builder, sources[sources.count - 1]);
	return builder_to_string(*builder, allocator = temp);
}

compile_shader_vf :: (src_vert : string, src_frag : string) -> Shader, ok:bool {
	vert, ok := compile_shader_part(src_vert, GL_VERTEX_SHADER);
	if !ok {
		print_color("failed to compile vertex shader\n", color = .RED);
		return .{}, false;
	}
	defer deinit(*vert);
	frag:, ok = compile_shader_part(src_frag, GL_FRAGMENT_SHADER);
	if !ok {
		print_color("failed to compile fragment shader\n", color = .RED);
		return .{}, false;
	}
	defer deinit(*frag);

	id := glCreateProgram();
	glAttachShader(id, vert.id);
	glAttachShader(id, frag.id);
	glLinkProgram(id);

	is_linked : GLint;
	glGetProgramiv(id, GL_LINK_STATUS, *is_linked);
	if !is_linked {
		max_length : GLint;
		glGetProgramiv(id, GL_INFO_LOG_LENGTH, xx *max_length);
		info_log := cast(string)NewArray(max_length, u8, allocator = temp);
		glGetProgramInfoLog(id, xx max_length, xx *info_log.count, info_log.data);
		print_color("failed to link shader:\n", color = .RED);
		print_color("%", info_log, color = .YELLOW);
		glDeleteProgram(id);
		return .{}, false;
	}
	return .{id = id}, true;
}
use :: (using s : *Shader) {
	// print("s = %, %\n", s, s.id);
	glUseProgram(id);
}
compile_shader_part :: (_source : string, type : u32) -> Shader_Part, ok:bool {
	source := join(GLSL_VERSION_LINE, _source, allocator = temp);
	id := glCreateShader(type);
	lines := split(source, cast(u8) #char "\n");

	builder := String_Builder.{allocator = temp};
	for id : 0..lines.count-1 {
		print_to_builder(*builder, "%\n", lines[id]);
	}
	append(*builder, "\0");
	c_src := builder_to_string(*builder, allocator = temp).data;

	glShaderSource(id, 1, *c_src, null);
	glCompileShader(id);

	success : s32;
	info_log_content : [512]s8;
	glGetShaderiv(id, GL_COMPILE_STATUS, *success);
	if !success {
		glGetShaderInfoLog(id, 512, null, cast(*GLchar) *info_log_content);
		info_log := from_c_string(*info_log_content);
		print_color("failed to compile shader: %", info_log, color = .RED);
		ok, info_log_parsed := scan("%d(%d)", info_log);
		if info_log_parsed.count >= 2 && info_log_parsed[1].type == type_info(int) {
			error_line := (cast(*int)(info_log_parsed[1].value_pointer)).*;
			source_lines := split(source, "\n");
			tabbed := true;
			for source_lines if it.count != 0 && it[0] != #char"\t" then tabbed = false;
			RANGE :: 2;
			L0, L1 := max(0, error_line - 1 - RANGE), min(error_line - 1 + RANGE, source_lines.count - 1);
			digits := log10(L1);
			for l : L0..L1 {
				line := source_lines[l];
				if tabbed && line {
					line.count -= 1;
					line.data += 1;
				}
				print_color("[%] %\n", formatInt(l + 1, minimum_digits = digits, padding = #char" "), line, color = .YELLOW);
			}
		} else {
			print_color("unable to parse error message\n", color = .YELLOW);
		}
		glDeleteShader(id);
		return .{}, false;
	}
	return .{id = id}, true;
}
deinit :: (sp : *Shader_Part) {
	glDeleteShader(sp.id);
}
deinit :: (using s : *Shader) {
	glDeleteProgram(id);
	deinit(*extra_fields);
}

find_id :: (s : *Shader, field : string) -> s32 {
	idptr, new := find_or_add(*s.extra_fields, field);
	if new {
		cstr_field := to_c_string(field);
		<<idptr = glGetUniformLocation(s.id, cstr_field);
		free(cstr_field);
	}
	return <<idptr;
}
set :: (s : *Shader, field : string, value : float) {
	glUniform1f(find_id(s, field), value);
}
set :: (s : *Shader, field : string, value : Vector2) {
	glUniform2f(find_id(s, field), value.x, value.y);
}
set :: (s : *Shader, field : string, value : Vector3) {
	glUniform3f(find_id(s, field), value.x, value.y, value.z);
}
set :: (s : *Shader, field : string, value : Matrix4) {
	glUniformMatrix4fv(find_id(s, field), 1, GL_TRUE, xx *value);
}
set :: (s : *Shader, field : string, value : u32) {
	glUniform1ui(find_id(s, field), value);
}
set :: (s : *Shader, field : string, value : s32) {
	glUniform1i(find_id(s, field), value);
}
set :: (s : *Shader, field : string, value : ivec2) {
	glUniform2i(find_id(s, field), value.x, value.y);
}

for_expansion :: (shader : *Shader, body : Code, flags : For_Flags) #expand {
	`set :: (name : string, value : $T) #expand {
		set(shader, name, value);
	}
	`it, `it_index := 0;

	use(shader);
	#insert body;
	glUseProgram(0);
}

// with :: (s : *Shader, code : Code, dimx : u32, dimy : u32 = 1, dimz : u32 = 1, barrier := GL_ALL_BARRIER_BITS, sizelim : u32 = 100000) #expand {
// 	assert(s.type == GL_COMPUTE_SHADER);
// 	set :: (field : string, value : $T) #expand {
// 		set(`s, field, value);
// 	}
// 	use(<<s);
// 	#insert,scope() code;
// 	compute(<<s, dimx, dimy, dimz, barrier, sizelim);
// }


// compile_part_with_preprocessor :: (source : string, options : Shader_Options) -> Shader_Src, ok:bool {
// 	//====
// }
// preprocess :: (source : string, options : Shader_Options) -> Shader_Src, ok:bool {
// 	lines := split(source, cast(u8) #char "\n");
// 	result : [..]string;
	
// }
// add_includes :: (source : Shader_Src, allocator := context.allocator, include_level := 5) -> Shader_Src, ok:bool {
// 	result : [..]string; result.allocator = allocator;
// 	for source {
// 		// words
// 	}

// }

// Shader_Src :: []string;
// shader_includes : Table(string, Shader_Src);
// deinit_shader_includes :: () {
// 	for shader_includes {
// 		array_free(it);
// 	}
// 	deinit(*shader_includes);
// }
// split_lines :: (text : string, allocator := context.allocator) -> Shader_Src {
// 	return split(text, cast(u8) #char "\n", allocator);
// }
// add_shader_lib :: (name : string, source : string) {
// 	table_add(shader_includes, name, split_lines(source));
// }