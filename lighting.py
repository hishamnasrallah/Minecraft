"""Shader that turns per-vertex light levels into final colours.

The chunk meshes store light in the vertex colour (r = sky light, g = block
light, b = face shade). Day/night only changes the `daylight` / `sky_tint`
shader inputs, so no chunk has to be rebuilt when the time changes.
"""
from ursina import Shader, Vec2

block_shader = Shader(name="block_shader", language=Shader.GLSL, vertex="""#version 130
uniform mat4 p3d_ModelViewProjectionMatrix;
in vec4 p3d_Vertex;
in vec2 p3d_MultiTexCoord0;
in vec4 p3d_Color;
out vec2 uvs;
out vec4 light;

void main() {
    gl_Position = p3d_ModelViewProjectionMatrix * p3d_Vertex;
    uvs = p3d_MultiTexCoord0;
    light = p3d_Color;
}
""", fragment="""#version 140
uniform sampler2D p3d_Texture0;
uniform vec4 p3d_ColorScale;
uniform float daylight;
uniform vec3 sky_tint;
in vec2 uvs;
in vec4 light;
out vec4 fragColor;

// brightness for a light level 0..1: gentle near the source, dark at 0
float curve(float level) { return pow(level, 1.6); }

void main() {
    vec4 tex = texture(p3d_Texture0, uvs);
    if (tex.a < 0.5) discard;               // see-through pixels (glass)
    vec3 sky = vec3(curve(light.r) * daylight) * sky_tint;
    vec3 lamp = vec3(curve(light.g)) * vec3(1.0, 0.86, 0.62);
    vec3 total = max(max(sky, lamp), vec3(0.03));
    fragColor = vec4(tex.rgb * total * light.b, tex.a * p3d_ColorScale.a);
}
""")
