Atoms_Painter :: struct(base_struct : Type) {
	vao, instance_vbo : u32;
	max_points : u32;
	buffer : [..]base_struct;
}
make_atoms_painter :: ($base_struct : Type, _max_points : u32) -> Atoms_Painter(base_struct) {
	using result : Atoms_Painter(base_struct) = .{max_points = _max_points};

	ti := type_info(base_struct);
	assert(ti.type == .STRUCT);
	tis := cast(*Type_Info_Struct)ti;

	acceptable_types 	:= *Type_Info.[
		type_info(float),
		type_info(Vector2),
		type_info(Vector3),
		type_info(Vector4),
		type_info(u32)
	];
	sizes 				:: u8.[1, 2, 3, 4, 1];
	categories 			:: GLenum.[GL_FLOAT, GL_FLOAT, GL_FLOAT, GL_FLOAT, GL_UNSIGNED_INT]; 

	glGenVertexArrays(1, *vao);
	glGenBuffers(1, *instance_vbo);

	glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, instance_vbo);
		glBufferData(GL_ARRAY_BUFFER, size_of(base_struct) * max_points, null, GL_STATIC_DRAW);

		for m, i : tis.members {
			member_type := m.type;
			type_id := -1;
			for acceptable_types {
				if it == member_type {
					type_id = it_index;
					break;
				}
			}
			assert(type_id != -1, "unsupported type (field = %)\n", m.name);
			glEnableVertexAttribArray(xx i);
			category := categories[type_id];
			if category == GL_FLOAT {
				glVertexAttribPointer(xx i, sizes[type_id], category, GL_FALSE, size_of(base_struct), xx m.offset_in_bytes);
			} else {
				glVertexAttribIPointer(xx i, sizes[type_id], category, size_of(base_struct), xx m.offset_in_bytes);
			}
			glVertexAttribDivisor(xx i, 1);
		}
	glBindBuffer(GL_ARRAY_BUFFER, 0);

	return result;
}
deinit :: (using atoms_painter : *Atoms_Painter($base_struct)) {
	glDeleteVertexArrays(1, *vao);
	glDeleteBuffers(1, *instance_vbo);
	array_reset(*buffer);
}
push :: (using atoms_painter : *Atoms_Painter($base_struct), object : base_struct) {
	if buffer.count < max_points then array_add(*buffer, object);
}
draw_simple :: (using atoms_painter : *Atoms_Painter($base_struct), vertices_per_instance : u32) {
	commit_buffer(atoms_painter);
	draw(atoms_painter, vertices_per_instance);
	reset(atoms_painter);
}
commit_buffer :: (using atoms_painter : *Atoms_Painter($base_struct)) {
	glBindBuffer(GL_ARRAY_BUFFER, instance_vbo);
	glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(base_struct) * buffer.count, buffer.data);	
	glBindBuffer(GL_ARRAY_BUFFER, 0);
}
draw :: (using atoms_painter : Atoms_Painter($base_struct), vertices_per_instance : u32 = 6) {
	glBindVertexArray(vao);
	glDrawArraysInstanced(GL_TRIANGLES, 0, vertices_per_instance, xx buffer.count);
}
reset :: (using atoms_painter : *Atoms_Painter($base_struct)) {
	array_reset(*buffer);
}
