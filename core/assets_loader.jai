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
	// animations   : [] GLTF_Animation;
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
}

Primitive :: struct {
	using mesh : Mesh;
	material_id : int;
}
draw :: (using primitive : Primitive, loaded_assets : Loaded_Assets) {
		check_gl_error();
	material := *loaded_assets.materials[material_id];
		check_gl_error();
	bind(material);
		check_gl_error();
	for material.textures.as_array {
		check_gl_error();
		if it == -1 continue;
		check_gl_error();
		bind_sampler(xx it_index, loaded_assets.textures[it]);
		check_gl_error();
	}
		check_gl_error();
	draw(mesh);
		check_gl_error();
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
		// joints 	: []u32;	// 4
		// weights : []float;	// 5
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

		mesh_src := Mesh_Source.{
			points = points,
			normals = normals,
			uvs_0 = uvs_0,
			indices = indices
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

	primitive_group := -1;

	children : [] int;
}
load_nodes :: (loaded_assets : *Loaded_Assets, gltf_data : GLTF_Data) {
	loaded_assets.nodes = NewArray(gltf_data.nodes.count, Object_Node);
	for * loaded_assets.nodes {
		using node := gltf_data.nodes[it_index];
		it.* = .{
			name,
			parent,
			world_transform,
			local_transform,
			mesh,
			array_copy(children)
		};
	}
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

draw_node :: (using loaded_assets : Loaded_Assets, i : int, extra_transform := Matrix4_Identity) {
		check_gl_error();
	node := nodes[i];
		check_gl_error();
	if node.primitive_group != -1 {
		check_gl_error();
		set_model_transform(extra_transform * node.world_transform);
		check_gl_error();
		draw(primitive_groups[node.primitive_group], loaded_assets);
		check_gl_error();
	}
	for node.children draw_node(loaded_assets, it, extra_transform);
}
load_assets :: (source : string) -> Loaded_Assets, root:int {
	loaded_assets : Loaded_Assets;
	gltf_data := gltf_parse_file(source);
	defer gltf_free(*gltf_data);
	gltf_load_buffers(*gltf_data);

	check_gl_error();
	texture_table := load_textures(*loaded_assets, gltf_data);
	check_gl_error();
	load_materials(*loaded_assets, gltf_data, texture_table);
	check_gl_error();
	deinit(*texture_table);
	check_gl_error();
	load_primitive_groups(*loaded_assets, gltf_data);
	check_gl_error();
	load_nodes(*loaded_assets, gltf_data);
	check_gl_error();

	root := -1;
	for loaded_assets.nodes {
		if it.parent == -1 {
			root = it_index;
		}
	}
	return loaded_assets, root;
}











