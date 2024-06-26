SSBO :: struct {
	id : u32;
}

make_ssbo :: (arr : []$T) -> SSBO {
	id : u32;
	glGenBuffers(1, *id);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, id);
	glBufferData(GL_SHADER_STORAGE_BUFFER, size_of(T) * arr.count, arr.data, GL_DYNAMIC_COPY);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
	return .{id};
}
make_ssbo_unfilled :: (size_in_bytes : u32) -> SSBO {
	id : u32;
	glGenBuffers(1, *id);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, id);
	glBufferData(GL_SHADER_STORAGE_BUFFER, size_in_bytes, null, GL_DYNAMIC_COPY);
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);	
	return .{id};
}
bind :: (slot : u32, ssbo : SSBO) {
	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, slot, ssbo.id); 
}
deinit :: (ssbo : *SSBO) {
	glDeleteBuffers(1, *ssbo.id);
}

SSBO_Dynamic :: struct(base_type : Type) {
	using base : SSBO;
	cpu_buffer : [..]base_type;
	gpu_max_elements : u32;
	fixed_part_size : u32;
}
bind :: (slot : u32, ssbo_dynamic : SSBO_Dynamic) {
	bind(slot, ssbo_dynamic.base);
}
deinit :: (using ssbo : *SSBO_Dynamic) {
	deinit(*base);
	array_free(cpu_buffer);
}

operator*[] :: (using ssbo_dynamic : *SSBO_Dynamic($T), i : int) -> *T {
	return *cpu_buffer[i];
}

make_ssbo_dynamic :: ($base_type : Type, max_elements : u32) -> SSBO_Dynamic(base_type) {
	result : SSBO_Dynamic(base_type);
	result.fixed_part_size = xx max(size_of(u32), align_of(base_type));
	result.gpu_max_elements = max_elements;
	result.base = make_ssbo_unfilled(max_elements * size_of(base_type) + result.fixed_part_size);
	return result;
}
push :: (using ssbo_dynamic : *SSBO_Dynamic($base_type), object : base_type) {
	array_add(*cpu_buffer, object);
}
commit :: (using ssbo_dynamic : *SSBO_Dynamic($base_type), reset_cpu_part := true, resize := false) -> u32 {
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, id);
	elements_on_gpu := min(cpu_buffer.count, gpu_max_elements);
	count : u32 = xx cpu_buffer.count;

	glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size_of(u32), *count);
	glBufferSubData(GL_SHADER_STORAGE_BUFFER, fixed_part_size, size_of(base_type) * elements_on_gpu, cpu_buffer.data);	
	glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
	if reset_cpu_part array_reset(*cpu_buffer);
	return xx elements_on_gpu;
}






