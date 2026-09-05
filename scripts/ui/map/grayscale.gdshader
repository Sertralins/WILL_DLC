shader_type canvas_item;

// 未解锁角色头像置灰
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g * 0.72 + 0.18), c.a);
}
