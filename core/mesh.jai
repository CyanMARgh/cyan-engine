Mesh_Type :: enum_flags u16 {
	NONE	:: 0x0000;

	NORMALS	:: 0x0002;
	TANGENTS:: 0x0004;
	COLORS	:: 0x0008;
	JOINTS	:: 0x0010;
	WEIGHTS	:: 0x0020;
	UVS_0	:: 0x0040;
	UVS_1	:: 0x0080;
	UVS_2	:: 0x0100;

	VBO 	:: 0x0200;
	EBO		:: 0x0400;
}

Mesh_Source :: struct {
	points 	: []float;	// 0
	normals : []float;	// 1
	// tangents: []float;	// 2
	// colors 	: []float;	// 3
	joints 	: []u32;	// 4
	weights : []float;	// 5
	uvs_0 	: []float;	// 5
	// uvs_1 	: []float;	// 6
	// uvs_2 	: []float;	// 7

	indices : []u32;
}
deinit :: (using mesh : *Mesh_Source) {
	array_free(points);
	array_free(normals);
	array_free(weights);
	array_free(joints);
	array_free(uvs_0);
	array_free(indices);
}

Mesh :: struct {
	vao, ebo, vbo : u32;

	points_count, indices_count : u32;
	mesh_type : Mesh_Type;

	draw_mode : s32;
}

get_mesh :: (using mesh_source : Mesh_Source, _draw_mode := GL_STATIC_DRAW) -> Mesh, ok:bool {
	using mesh : Mesh;
	draw_mode = xx _draw_mode;
	mesh_type |= .VBO;

	if points.count % 3 || points.count <= 0 return .{}, false;
	points_count = xx (points.count / 3);

	if normals {
		mesh_type |= .NORMALS;
		if normals.count % 3 || points_count != normals.count / 3 return .{}, false;
	}
	if uvs_0 {
		mesh_type |= .UVS_0;
		if uvs_0.count % 2 || points_count != uvs_0.count / 2 return .{}, false;
	}
	if indices {
		mesh_type |= .EBO;
		if indices.count % 3 return .{}, false;
		indices_count = xx indices.count;
	} else {
		if points_count % 3 return .{}, false;
	}
	if joints {
		mesh_type |= .JOINTS;
		if joints.count % 4 return .{}, false;
		if points_count != joints.count / 4 return .{}, false;
	}
	if weights {
		mesh_type |= .WEIGHTS;
		if weights.count % 4 return .{}, false;
		if points_count != weights.count / 4 return .{}, false;
	}

	glGenVertexArrays(1, *vao);
	glGenBuffers(1, *vbo);

	glBindVertexArray(vao);
	glBindBuffer(GL_ARRAY_BUFFER, vbo);

	if mesh_type & .EBO {
		glGenBuffers(1, *ebo);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.count * size_of(u32), indices.data, xx draw_mode);
	}

	arr_size :: (arr : []$T) -> int { return size_of(T) * arr.count; }
	offset_in_bytes := 0;
	add_attrib :: (arr : []$T1, T2 : Type, id : int) #expand {
		block_size := arr_size(arr);
		glBufferSubData(GL_ARRAY_BUFFER, xx offset_in_bytes, block_size, xx arr.data);
		#if T1 == float {
			#run assert(T2 == float || T2 == Vector2 || T2 == Vector3 || T2 == Vector4, "unsupported type");
			glVertexAttribPointer(id, xx (size_of(T2) / size_of(float)), GL_FLOAT, GL_FALSE, 0, xx offset_in_bytes);
		} else if T1 == u32 {
			#run assert(T2 == u32 || T2 == ivec2 || T2 == ivec4, "unsupported type");
			glVertexAttribIPointer(id, xx (size_of(T2) / size_of(u32)), GL_INT, 0, xx offset_in_bytes);

		}
		glEnableVertexAttribArray(id);
		offset_in_bytes += block_size;
	}

	total_size_in_bytes := arr_size(points) + arr_size(normals) + arr_size(uvs_0);
	glBufferData(GL_ARRAY_BUFFER, total_size_in_bytes, null, xx draw_mode);

	add_attrib(points, Vector3, 0);
	if mesh_type & .NORMALS add_attrib(normals, Vector3, 1);
	if mesh_type & .UVS_0 {
		add_attrib(uvs_0, Vector2, 5);
	} else {
		glVertexAttrib2fv(5, float.[1., .5].data);			
	}
	if mesh_type & .JOINTS add_attrib(joints, ivec4, 4);
	if mesh_type & .WEIGHTS add_attrib(weights, Vector4, 4);

	glBindVertexArray(0);
	return mesh, true;
}
get_empty_mesh :: () -> Mesh {
	using mesh : Mesh;
	glGenVertexArrays(1, *vao);
	return mesh;
}
draw :: (using mesh : Mesh, mode := GL_TRIANGLES, actual_size :u32= 0xFFFFFFFF) {
	glBindVertexArray(vao);
	if mesh_type & .EBO {
		glDrawElements(xx mode, ifx actual_size == 0xFFFFFFFF then indices_count else actual_size, GL_UNSIGNED_INT, null);
	} else if mesh_type & .VBO {
		glDrawArrays(xx mode, 0, ifx actual_size == 0xFFFFFFFF then points_count else actual_size);
	} else {
		assert(actual_size != 0xFFFFFFFF);
		glDrawArrays(xx mode, 0, actual_size);
	}
	glBindVertexArray(0);
}
draw_instanced :: (using mesh : Mesh, instances : u32, mode := GL_TRIANGLES, actual_size :u32= 0xFFFFFFFF) {
	glBindVertexArray(vao);	
	if mesh_type & .EBO {
		glDrawElementsInstanced(xx mode, ifx actual_size == 0xFFFFFFFF then indices_count else actual_size, GL_UNSIGNED_INT, null, instances);
	} else if mesh_type & .VBO {
		glDrawArraysInstanced(xx mode, 0, ifx actual_size == 0xFFFFFFFF then points_count else actual_size, instances);
	} else {
		assert(actual_size != 0xFFFFFFFF);
		glDrawArraysInstanced(xx mode, 0, actual_size, instances);
	}
	glBindVertexArray(0);
}

deinit :: (using mesh : *Mesh) {
	glDeleteVertexArrays(1, *vao);
	if mesh_type & .VBO {
		glDeleteBuffers(1, *vbo);
	}
	if mesh_type & .EBO {
		glDeleteBuffers(1, *ebo);
	}
}

