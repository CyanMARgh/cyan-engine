UBO :: struct {
	id : u32;
	type : *Type_Info;
}
make_ubo :: ($T : Type) -> UBO {
	id : u32;
	glGenBuffers(1, *id);
	glBindBuffer(GL_UNIFORM_BUFFER, id);
		glBufferData(GL_UNIFORM_BUFFER, size_of(T), null, GL_STATIC_DRAW);
	glBindBuffer(GL_UNIFORM_BUFFER, 0);
	return .{id, type_info(T)};
}
make_ubo_initialized :: (data : $T) -> UBO {
	id : u32;
	glGenBuffers(1, *id);
	glBindBuffer(GL_UNIFORM_BUFFER, id);
		glBufferData(GL_UNIFORM_BUFFER, size_of(T), *data, GL_STATIC_DRAW);
	glBindBuffer(GL_UNIFORM_BUFFER, 0);
	return .{id, type_info(T)};
}
bind :: (slot : u32, ubo : UBO) {
	glBindBufferBase(GL_UNIFORM_BUFFER, slot, ubo.id); 
}
set_value :: (using ubo : *UBO, data : $T) {
	assert(type == type_info(T));
	glBindBuffer(GL_UNIFORM_BUFFER, id);
		glBufferSubData(GL_UNIFORM_BUFFER, 0, size_of(T), *data);
	glBindBuffer(GL_UNIFORM_BUFFER, 0);
}

deinit :: (using ubo : *UBO) {
	glDeleteBuffers(1, *id);
}
