Camera :: struct {
	yaw, pitch/*, roll*/ : float;
	position : Vector3;

	near, far := .1, 1000.;
	fow_vertical := PI * .3;
	screen_size : ivec2;
}

Movable_Camera :: struct {
	#as using camera : Camera;

	linear_speed, keyboard_angular_speed, angular_speed := 10., .15, .002;
	pitch_limit := PI * .5;
}

update_camera :: (using movable_camera : *Movable_Camera, target_screen_size : ivec2, movement := true) -> updated : bool {
	using backend_state;
	updated := false;
	if screen_size != target_screen_size { screen_size = target_screen_size; updated = true; }
	if movement {
		d_yaw, d_pitch := 0.;
		direction : Vector3;

		if keys_down[#char "W"]	{ direction.z -= 1; updated = true; }
		if keys_down[#char "S"]	{ direction.z += 1; updated = true; }
		if keys_down[#char "A"]	{ direction.x -= 1; updated = true; }
		if keys_down[#char "D"]	{ direction.x += 1; updated = true; }
		if keys_down[#char " "]	{ direction.y += 1; updated = true; }	
		if keys_down[GLFW_KEY_LEFT_SHIFT] { direction.y -= 1; updated = true; }	

		if keys_down[#char "Q"]	{ d_yaw   += 10; updated = true; }
		if keys_down[#char "E"]	{ d_yaw   -= 10; updated = true; }
		if keys_down[#char "R"]	{ d_pitch += 10; updated = true; }
		if keys_down[#char "F"]	{ d_pitch -= 10; updated = true; }

		d_yaw *= keyboard_angular_speed * delta_time;
		d_pitch *= keyboard_angular_speed * delta_time;

		if cursor_delta != .{} {
			d_yaw -= cursor_delta.x * angular_speed;
			d_pitch -= cursor_delta.y * angular_speed;
			updated = true;
		}

		yaw += d_yaw;
		pitch += d_pitch;
		Clamp(*pitch, -pitch_limit, pitch_limit);
		yaw = fmod_cycling(yaw, 2 * PI);

		direction = rotate(direction, Quaternion.{0, sin(yaw / 2), 0, cos(yaw / 2)});
		position += direction * linear_speed * delta_time * (ifx keys_down[GLFW_KEY_LEFT_CONTROL] then 3. else 1.);
	}
	return updated;
}

UBO_Content_Camera :: struct {
	mat_t, mat_r, mat_p : Matrix4;
	mat_trp : Matrix4;

	near, far : float;
	width_over_height : float;
	eye : Vector3 #align 16;
}

to_ubo_content :: (using camera : Camera) -> UBO_Content_Camera {
	mat_t := make_translation_matrix4(-position);
	mat_r := rotation_matrix(Matrix4,
		Quaternion.{sin(-pitch / 2), 0, 0, cos(-pitch / 2)} * 
		Quaternion.{0, sin(-yaw / 2), 0, cos(-yaw / 2)}		
	);
	width_over_height := screen_size.x / cast(float)screen_size.y;
	mat_p := make_projection_matrix(fow_vertical, width_over_height, near, far); 

	return .{
		transpose(mat_t), transpose(mat_r), transpose(mat_p),
		transpose(mat_p * mat_r * mat_t),
		near, far,
		width_over_height,
		position
	};
}