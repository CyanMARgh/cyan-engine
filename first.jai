#import "Compiler";
#import "Basic";
#import "File";
#import "Process";
#import "Print_Color";
DEBUG :: true;

// TODO slice atom_painter to 2 structs (1 - sends data to gpu and draws it, 2 - handles draw_quad(), simulate(), etc. ) 
// TODO push_transformation();
// TODO unhandled: mipmap & non-default sampling params 
// TODO split texture to smapler & texture base
// TODO fix slowdown with 120fps
// TODO SDF and outline on/off for font
// TODO font codepoints ranges
// TODO move font size to ssbo maybe
// TODO add u_mat_t for font
// TODO massive primitives renderer (circles without "discard" or gl_FragDepth)
// TODO parameteric 3d primitives renderer (cylinder, sphere, torus, cube) => instancing => multiple cpu-buffers
// TODO atomics painter: autogenerate attributes header

BUILD_AND_RUN_ALL :: false;
TOTAL_DEMOS :: 10;
DEMO_ID :: 9;

#run {
	set_build_options_dc(.{do_output = false});
	if BUILD_AND_RUN_ALL {
		for 0..TOTAL_DEMOS-1 {
			if !build(it, true) break;
			make_link(it);
			run_command("./main", #filepath);
		}
	} else {
		if build(DEMO_ID) make_link(DEMO_ID);
	}
}

EXECS_DIR :: "execs";
EXE_SUFFIX :: "";

make_link :: (id : int) {
	run_command("ln", "-s", "-f", tprint("./%1/main_%2%3", EXECS_DIR, id, EXE_SUFFIX), tprint("main%", EXE_SUFFIX));
}

build :: (id : int, run := false) -> bool {
	root := tprint("demos/demo_%.jai",id);
	w := compiler_create_workspace(root);
	if !w {
		print("Workspace creation failed.\n");
		exit(-1);
	}
	target_options := get_build_options(w);
	{
		using target_options;
		set_optimization(*target_options, ifx DEBUG then .VERY_DEBUG else .OPTIMIZED, !DEBUG);
		#if DEBUG {
			backend = .X64;
		} else {
			// backend = .LLVM;
			emit_debug_info = .NONE;
		}

		text_output_flags = 0;
		output_executable_name = tprint("main_%1", id);
		output_path = "execs";
		import_path = .[import_path[0], ".."];
	}
	set_build_options(target_options, w);

	make_directory_if_it_does_not_exist(EXECS_DIR);

	compiler_begin_intercept(w);
	add_build_file(tprint("%/%", #filepath, root), w);
	#if OS == .WINDOWS add_build_string("#run (#import \"Windows_Resources\").disable_runtime_console();", w);
	ok := true;
	while 1 {
		message := compiler_wait_for_message();
		if message.kind == {
			case .COMPLETE;
			if (cast(*Message_Complete)message).error_code != .NONE then ok = false;
			break;
		}
	}
	compiler_end_intercept(w);
	print_color("build #% %\n", id, ifx ok then "finished" else "failed", color = ifx ok then .GREEN else .RED);
	return ok;
}


