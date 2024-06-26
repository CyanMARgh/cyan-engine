Loaded_Assets :: struct {
	textures	: [] Texture;
	materials	: [] Material;
	primitive_groups : [] Primitive_Group;
	nodes		: [] Object_Node;
	// asset        : GLTF_Asset;
	// scene        : int;
	// scenes       : [] GLTF_Scene;
	// skins        : [] GLTF_Skin;
	// cameras      : [] GLTF_Camera;
	// lights       : [] GLTF_Light;
	animations	: [] Animation;
	roots 		: [] int;
}
deinit :: (using loaded_assets : *Loaded_Assets) {
	for * primitive_groups deinit(it);
	array_free(primitive_groups);
	for nodes array_free(it.children);
	array_free(nodes);
	for * textures deinit(it);
	array_free(textures);
	for * materials deinit(it);
	array_free(materials);
	for * animations deinit(it);
	array_free(animations);
	array_free(roots);
}

Primitive :: struct {
	using mesh : Mesh;
	material_id : int;
}
draw :: (using primitive : Primitive, loaded_assets : Loaded_Assets) {
	material : Material;
	if material_id >= 0 && material_id < loaded_assets.materials.count {
		material = *loaded_assets.materials[material_id];
		bind(material);
		for material.textures.as_array {
			if it == -1 continue;
			bind(xx it_index, loaded_assets.textures[it]);
		}		
	} else {

	}
	draw(mesh);
}
deinit :: (using primitive : *Primitive) {
	deinit(*mesh);
}
Primitive_Group :: struct {
	name : string;
	primitives : []Primitive;
}
draw :: (using primitive_group : Primitive_Group, loaded_assets : Loaded_Assets) {
	for primitives draw(it, loaded_assets);
}
deinit :: (using primitive_group : *Primitive_Group) {
	for * primitives deinit(it);
	array_free(primitives);
	free(name);
}
load_primitive :: (gltf_data : GLTF_Data, primitive : GLTF_Primitive) -> Primitive {
	ctx := context;
	ctx.allocator = temp;
	push_context ctx {
		points 	: [..]float;	// 0
		normals : [..]float;	// 1
		// tangents: []float;	// 2
		// colors 	: []float;	// 3
		joints 	: [..]u32;	    // 4
		weights : [..]float;    // 5
		uvs_0 	: [..]float;	// 5
		// uvs_1 	: []float;	// 6
		// uvs_2 	: []float;	// 7
		indices : [..]u32;

		if primitive.position_accessor != -1 {
			accessor := gltf_data.accessors[primitive.position_accessor];
			read_buffer_from_accessor(*gltf_data, accessor, *points);
		}
		if primitive.normal_accessor != -1 {
			accessor := gltf_data.accessors[primitive.normal_accessor];
			read_buffer_from_accessor(*gltf_data, accessor, *normals);
		}
		if primitive.texcoord_0_accessor != -1 {
			accessor := gltf_data.accessors[primitive.texcoord_0_accessor];
			read_buffer_from_accessor(*gltf_data, accessor, *uvs_0);
		}
		if primitive.indices_accessor != -1 {
			accessor := gltf_data.accessors[primitive.indices_accessor];
			read_buffer_from_accessor(*gltf_data, accessor, *indices);
		}
		if primitive.weights_accessor != -1 {
			accessor := gltf_data.accessors[primitive.weights_accessor];
			read_buffer_from_accessor(*gltf_data, accessor, *weights);
		}
		if primitive.joints_accessor != -1 {
			accessor := gltf_data.accessors[primitive.joints_accessor];
			read_buffer_from_accessor(*gltf_data, accessor, *joints);
		}


		mesh_src := Mesh_Source.{
			points = points,
			normals = normals,
			uvs_0 = uvs_0,
			indices = indices,
			joints = joints,
			weights = weights
		};
		return .{get_mesh(mesh_src), primitive.material};
	}
}
load_primitive_group :: (gltf_data : GLTF_Data, gltf_mesh : GLTF_Mesh) -> Primitive_Group {
	using mesh_group : Primitive_Group;
	primitives = NewArray(gltf_mesh.primitives.count, Primitive);
	for gltf_mesh.primitives {
		primitives[it_index] = load_primitive(gltf_data, it);
	}
	name = copy_string(gltf_mesh.name);

	return mesh_group;
}
load_primitive_groups :: (loaded_assets : *Loaded_Assets, gltf_data : GLTF_Data) {
	loaded_assets.primitive_groups = NewArray(gltf_data.meshes.count, Primitive_Group);
	for gltf_data.meshes {
		loaded_assets.primitive_groups[it_index] = load_primitive_group(gltf_data, it);
	}
}
Object_Node :: struct {
	name : string;
	parent := -1;
	world_transform : Matrix4;
	local_transform : Matrix4;
	
	translation : Vector3;
	scale := Vector3.{1, 1, 1};
	rotation : Quaternion;

	primitive_group := -1;

	children : [] int;
}
load_nodes :: (loaded_assets : *Loaded_Assets, gltf_data : GLTF_Data) {
	loaded_assets.nodes = NewArray(gltf_data.nodes.count, Object_Node);

	roots : [..]int;
	for * loaded_assets.nodes {
		using node := gltf_data.nodes[it_index];
		// print("node #% = %\n\n", it_index, node);
		it.* = .{
			name,
			parent,
			world_transform,
			local_transform,

			.{component = translation},
			.{component = scale},
			.{component = rotation},

			mesh,
			array_copy(children)
		};
		if it.parent == -1 {
			array_add(*roots, it_index);
		}
	}
	loaded_assets.roots = roots;
}
get_sampler :: (id : int, gltf_data : GLTF_Data) -> GLTF_Sampler {
	if id == -1 return .{};
	return gltf_data.samplers[id];
}
load_texture_from_file :: (path : string, using sampling_options : GLTF_Sampler) -> Texture, ok:bool {
	texture, ok := load_texture_from_file(path, 3, xx mag_filter, xx min_filter, xx wrap_s, xx wrap_t);
	return texture, ok;
}
hash_2int :: (a : [2]int) -> u32 { return cast,trunc(u32)((a[0] << 16) ^ a[1]); }
cmp_2int :: (a : [2]int, b : [2]int) -> bool { return a[0] == b[0] && a[1] == b[1]; }
Texture_Table :: Table([2]int, int, hash_2int, cmp_2int);

load_textures :: (loaded_assets : *Loaded_Assets, gltf_data : GLTF_Data) -> texture_table:Texture_Table, ok:bool, info:string {
	texture_table : Texture_Table;
	textures : [..]Texture;

	source_folder_path := path_decomp(gltf_data.filepath);
	for gltf_data.textures {
		ptr, new := find_or_add(*texture_table, .[it.sampler, it.source]);
		if new {
			ptr.* = texture_table.count-1;
			source_path := tprint("%/%", source_folder_path, gltf_data.images[it.source].uri);
			texture, ok := load_texture_from_file(
				source_path,
				get_sampler(it.sampler, gltf_data)
			);
			if !ok {
				deinit(*texture_table);
				return .{}, false, tprint("failed to load: %\n", source_path);
			}
			array_add(*textures, texture);
		}
	}
	loaded_assets.textures = textures;

	return texture_table, true, "";
}
Material :: struct {
	name : string;
	is_name_on_heap := false;
	ubo : UBO;

	using ubo_content : struct {
		flags : enum_flags u32 {
			NONE				:: 0x0;

			BASE_COLOR 			:: 0x1;
			METALLIC_ROUGHNESS 	:: 0x2;
			NORMAL 				:: 0x4;
			OCCLUSION 			:: 0x8;
			EMISSIVE			:: 0x10;
			DOUBLE_SIDED 		:: 0x20;
			TRANSMISSION 		:: 0x40;

			ALPHA_MODE 			:: 0x380;
			OPAQUE				:: 0x080;
			MASK				:: 0x100;
			BLEND				:: 0x200;
		} = .NONE;
		base_color_factor 		:= Vector4.{1, 1, 1, 1} #align 16;
		metallic_factor   		:= 1.;
		roughness_factor  		:= 1.;
		emissive_factor 		:= Vector3.{0, 0, 0} #align 16;
		transmission_factor 	:= 0.0;

		alpha_cutoff 			:= 0.5;
		ior 					:= 1.5;
		emissive_strength 		:= 1.0;

		normal_scale 			:= 1.;
		occlusion_strength 		:= 1.;
	}
	textures : struct {
		base_color 				: int;
		metallic_roughness 		: int;
		normal    				: int;
		occlusion 				: int;
		emissive  				: int;
		transmission 			: int;
		#place base_color;
		as_array 				: [6]int;
	};
}
bind :: (material : Material) {
	bind(4, material.ubo);
}
deinit :: (using material : *Material) {
	deinit(*ubo);
	if is_name_on_heap free(name);
}
load_material :: (using gltf_material : GLTF_Material, gltf_data : GLTF_Data, texture_table : Texture_Table) -> Material, ok:bool {
	set_field :: (texture_field : *int, texture_info : GLTF_Texture_Info) #expand {
		texture_id := texture_info.index;
		if texture_id == -1 {
			texture_field.* = -1;
		} else {
			texture := gltf_data.textures[texture_id];
			id, ok := table_find(*texture_table, .[texture.sampler, texture.source]);
			if !ok `return .{}, false;
			texture_field.* = id;
		}
	}
	material := Material.{
		base_color_factor.component = metallic_roughness.base_color_factor,
		metallic_factor = metallic_roughness.metallic_factor,
		roughness_factor = metallic_roughness.roughness_factor,
		emissive_factor.component = emissive_factor,
		transmission_factor = transmission_factor,

		alpha_cutoff = alpha_cutoff,
		ior = ior,
		emissive_strength = emissive_strength,
		normal_scale = normal_texture.scale,
		occlusion_strength = occlusion_texture.strength,
	};
	set_field(*material.textures.base_color, metallic_roughness.base_color_texture);
	set_field(*material.textures.metallic_roughness, metallic_roughness.metallic_roughness_texture);
	set_field(*material.textures.normal, normal_texture);
	set_field(*material.textures.occlusion, occlusion_texture);
	set_field(*material.textures.emissive, emissive_texture);
	set_field(*material.textures.transmission, transmission_texture);

	material.flags = 
		(ifx metallic_roughness.has_base_color then .BASE_COLOR else .NONE) |
		(ifx metallic_roughness.has_metallic_roughness then .METALLIC_ROUGHNESS else .NONE) |
		(ifx has_normal then .NORMAL else .NONE) |
		(ifx has_occlusion then .OCCLUSION else .NONE) |
		(ifx has_emissive then .EMISSIVE else .NONE) |
		(ifx has_transmission then .TRANSMISSION else .NONE) |
		(ifx alpha_mode == .OPAQUE then .OPAQUE else ifx alpha_mode == .MASK then .MASK else .BLEND) |
		(ifx is_double_sided then .DOUBLE_SIDED else .NONE)
	;

	material.name = copy_string(name);
	material.is_name_on_heap = true;
	material.ubo = make_ubo_initialized(material.ubo_content);
	return material, true;
}
send_to_gpu :: (material : *Material) {
	if material.ubo.id {
		set_value(*material.ubo, material.ubo_content);
	} else {
		material.ubo = make_ubo_initialized(material.ubo_content);
	}
}
load_materials :: (loaded_assets : *Loaded_Assets, gltf_data : GLTF_Data, texture_table : Texture_Table) -> ok:bool {
	loaded_assets.materials = NewArray(gltf_data.materials.count, Material);
	for gltf_data.materials {
		ok : bool;
		loaded_assets.materials[it_index], ok = load_material(it, gltf_data, texture_table);
		if !ok return false;
	}
	return true;
}
Animation :: struct {
	Channel :: struct {
		node : int;
		property : GLTF_Target_Property; 
		// TRANSLATION, ROTATION, SCALE, WEIGHTS
		interpolation : GLTF_Interpolation;
		// LINEAR, STEP, CUBICSPLINE
		timestamps : []float; //TODO maybe make shared
		values : []float;
	}
	channels : []Channel;
	delay : float;
}

deinit :: (using channel : *Animation.Channel) {
	array_free(timestamps);
	array_free(values);
}
deinit :: (using animation : *Animation) {
	for * channels deinit(it);
	array_free(channels);
}

load_animations :: (loaded_assets : *Loaded_Assets, gltf_data : GLTF_Data) {
	load_animation :: (gltf_animation : GLTF_Animation) -> Animation #expand {
		load_channel :: (gltf_channel : GLTF_Channel) -> Animation.Channel #expand {
			channel : Animation.Channel;
			channel.node = gltf_channel.target.node;
			channel.property = gltf_channel.target.property;
			sampler := gltf_animation.samplers[gltf_channel.sampler];
			channel.interpolation = sampler.interpolation;

			timestamps : [..]float;
			values : [..]float;
			read_buffer_from_accessor(*gltf_data, gltf_data.accessors[sampler.input], *timestamps);
			read_buffer_from_accessor(*gltf_data, gltf_data.accessors[sampler.output], *values);
			channel.timestamps = timestamps;
			channel.values = values;
			assert(timestamps.count > 0);
			// assert compare sizes
			return channel;
		}
		animation : Animation;
		animation.channels = NewArray(gltf_animation.channels.count, Animation.Channel);
		for gltf_animation.channels {
			channel := load_channel(it);
			animation.channels[it_index] = channel;
			animation.delay = max(animation.delay, channel.timestamps[channel.timestamps.count - 1]);
		}
		return animation;
	}
	loaded_assets.animations = NewArray(gltf_data.animations.count, Animation);
	for gltf_data.animations {
		loaded_assets.animations[it_index] = load_animation(it);
	}
}

interpolate :: (t : float, t0 : float, t1 : float, v0 : float, v1 : float, interpolation : GLTF_Interpolation) -> float {
	assert(t0 <= t && t <= t1);
	if interpolation == .STEP {
		return v0;
	} else if interpolation == .LINEAR {
		return v0 + (t - t0) * (v1 - v0) / (t1 - t0);
	} else {
		assert(false, "not supported yet");
		return 0;
	}
}
interpolate :: (dest : *float, timestamps : []float, values : []float, interpolation : GLTF_Interpolation, dims : int, time : float) {
	assert(timestamps.count * dims == values.count);
	if time <= timestamps[0] {
		for i : 0..dims-1 {
			dest[i] = values[i];
		}
		return;
	} 
	if time >= timestamps[timestamps.count - 1] {
		for i : 0..dims-1 {
			dest[i] = values[dims * (timestamps.count - 1) + i];
		}
		return;
	}

	left, right := 0, timestamps.count - 1;
	while right > left + 1 {
		center := (left + right) / 2;
		tc := timestamps[center];
		if tc > time {
			right = center;
		} else {
			left = center;
		}
	}
	for i : 0..dims-1 {
		dest[i] = interpolate(time, timestamps[left], timestamps[right], values[left * dims + i], values[right * dims + i], interpolation);
	}
}
interpolate :: (dest : *$T, using channel : Animation.Channel, time : float) {
	#if (T == Vector4) || (T == [4]float) || (T == Quaternion) {
		DIMS :: 4;
		assert(property == .ROTATION);
	} else #if T == Vector3 || T == [3]float {
		DIMS :: 3;
		assert(property == .SCALE || property == .TRANSLATION);
	} else {
		DIMS :: 0;
		#assert false;
	}
	interpolate(xx dest, channel.timestamps, channel.values, channel.interpolation, DIMS, time);
}

apply_animation :: (loaded_assets : *Loaded_Assets, animation_id : int, time : float) {
	for loaded_assets.animations[animation_id].channels {
		// using it;
		node := *loaded_assets.nodes[it.node];
		if it.property == {
			case .TRANSLATION;
			interpolate(*node.translation, it, time);
			// print("node.translation = %\n", node.translation);
			case .ROTATION;
			interpolate(*node.rotation, it, time);
			normalize_or_identity(*node.rotation);
			// print("node.rotation = %\n", node.rotation);
			case .SCALE;
			interpolate(*node.scale, it, time);			
			// print("node.scale = %\n", node.scale);
		}
		node.local_transform = 
			make_translation_matrix4(node.translation)
			 *
			rotation_matrix(Matrix4, node.rotation)

			;
	}
}

draw_node :: (using loaded_assets : Loaded_Assets, i : int, extra_transform := Matrix4_Identity) {
	node := nodes[i];
	// print("local_transform")
	this_object_transform := extra_transform * node.local_transform;
	if node.primitive_group != -1 {
		set_model_transform(graphics_state.scene_translation * this_object_transform);
		draw(primitive_groups[node.primitive_group], loaded_assets);
	}
	for node.children draw_node(loaded_assets, it, this_object_transform);
}

draw_root :: (using loaded_assets : Loaded_Assets, id : int) {
	draw_node(loaded_assets, roots[id]);
}
draw_all_roots :: (using loaded_assets : Loaded_Assets) {
	for roots {
		draw_node(loaded_assets, it);
	}
}

load_assets :: (source : string) -> Loaded_Assets {
	loaded_assets : Loaded_Assets;
	gltf_data := gltf_parse_file(source);
	defer gltf_free(*gltf_data);
	gltf_load_buffers(*gltf_data);

	texture_table := load_textures(*loaded_assets, gltf_data);
	load_materials(*loaded_assets, gltf_data, texture_table);
	deinit(*texture_table);
	load_primitive_groups(*loaded_assets, gltf_data);
	load_nodes(*loaded_assets, gltf_data);
	load_animations(*loaded_assets, gltf_data);

	return loaded_assets;
}











