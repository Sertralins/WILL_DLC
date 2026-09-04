// scroll_blocks.gdshader —— 倒计时色彩条斜纹(仿 assets/example/滚动条.png 形状)
// 条纹如 "/"(顶部偏右), 主题色与白色交替; 图案沿竖直方向平移(与条带垂直),
// 视觉上斜纹持续朝右下角流动(理发店灯柱效果)。
// 参数按原图 569×125 实测: 斜率 dx/dy=1.808 → UV 斜率 0.397(条带宽高比不变);
// 周期 191px/569 ≈ 0.336; 占空比 95/191 ≈ 0.5。
shader_type canvas_item;

uniform vec4 stripe_color : source_color = vec4(0.85, 0.3, 0.3, 1.0); // 主题色条纹(按行角色色)
uniform vec4 gap_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);     // 白色条纹
uniform float scroll : hint_range(0.0, 1.0) = 0.0;    // 相位, 递增 → 斜纹朝右下角流动
uniform float slant : hint_range(0.0, 2.0) = 0.397;   // 斜纹斜率(UV 单位)
uniform float period : hint_range(0.1, 1.0) = 0.336;  // 斜纹周期(占条宽比例)
uniform float duty : hint_range(0.1, 0.9) = 0.5;      // 主题色条纹占空比

void fragment() {
	float m = mod(UV.x + slant * UV.y - scroll, period);
	COLOR = m <= duty * period ? stripe_color : gap_color;
}
