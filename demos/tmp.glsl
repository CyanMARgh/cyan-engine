#version 450 core

const float PI = 3.141592;
const float Epsilon = 0.00001;
const vec3 Fdielectric = vec3(0.04);
#define LOD_MAX_LEVEL 5

in struct VO {
	vec3 position;
	vec3 normal;
	vec2 uv_0;
} vo;

out vec4 o_color;

// const int NumLights = 3;
// struct AnalyticalLight {
// 	vec3 direction;
// 	vec3 radiance;
// };
// layout(std140, binding = 1) uniform ShadingUniforms {
// 	AnalyticalLight lights[NumLights];
// 	vec3 eyePosition;
// };

float ndfGGX(float cosLh, float roughness) {
	float alpha   = roughness * roughness;
	float alphaSq = alpha * alpha;

	float denom = (cosLh * cosLh) * (alphaSq - 1.0) + 1.0;
	return alphaSq / (PI * denom * denom);
}

float gaSchlickG1(float cosTheta, float k) {
	return cosTheta / (cosTheta * (1.0 - k) + k);
}

float gaSchlickGGX(float cosLi, float cosLo, float roughness) {
	float r = roughness + 1.0;
	float k = (r * r) / 8.0; // Epic suggests using this roughness remapping for analytic lights.
	return gaSchlickG1(cosLi, k) * gaSchlickG1(cosLo, k);
}
vec3 fresnelSchlick(vec3 F0, float cosTheta) {
	return F0 + (vec3(1.0) - F0) * pow(1.0 - cosTheta, 5.0);
}

uniform float u_metallic;
uniform float u_roughness;
void main() {
	// vec3 albedo = texture(albedoTexture, vin.texcoord).rgb;
	// float metallic = texture(metallicTexture, vin.texcoord).r;
	// float roughness = texture(roughnessTexture, vin.texcoord).r;
	vec3 albedo = vec3(1, 1, 1);
	float metallic = u_metallic;
	float roughness = u_roughness;

	vec3 Lo = normalize(u_eye - vo.position);
	vec3 N = normalize(vo.normal);
	
	float cosLo = max(0.0, dot(N, Lo));
	vec3 Lr = 2.0 * cosLo * N - Lo;

	vec3 F0 = mix(Fdielectric, albedo, metallic);

	vec3 directLighting = vec3(0);
	for(int i=0; i<1; ++i)
	{
		// vec3 Li = -lights[i].direction;
		// vec3 Lradiance = lights[i].radiance;
		vec3 Li = normalize(vec3(1, 1, 1));
		vec3 Lradiance = vec3(1, 1, 1);

		vec3 Lh = normalize(Li + Lo);

		float cosLi = max(0.0, dot(N, Li));
		float cosLh = max(0.0, dot(N, Lh));

		vec3 F  = fresnelSchlick(F0, max(0.0, dot(Lh, Lo)));
		float D = ndfGGX(cosLh, roughness);
		float G = gaSchlickGGX(cosLi, cosLo, roughness);

		vec3 kd = mix(vec3(1.0) - F, vec3(0.0), metallic);

		vec3 diffuseBRDF = kd * albedo;

		vec3 specularBRDF = (F * D * G) / max(Epsilon, 4.0 * cosLi * cosLo);

		directLighting += (diffuseBRDF + specularBRDF) * Lradiance * cosLi;
	}

	vec3 ambientLighting;
	{
		vec3 irradiance = textureLod(u_skybox, N, LOD_MAX_LEVEL).rgb;

		vec3 F = fresnelSchlick(F0, cosLo);

		vec3 kd = mix(vec3(1.0) - F, vec3(0.0), metallic);

		vec3 diffuseIBL = kd * albedo * irradiance;

		vec3 specularIrradiance = textureLod(u_skybox, Lr, roughness * LOD_MAX_LEVEL).rgb;

		vec2 specularBRDF = texture(u_brdf, vec2(cosLo, roughness)).rg;

		vec3 specularIBL = (F0 * specularBRDF.x + specularBRDF.y) * specularIrradiance;
		ambientLighting = diffuseIBL + specularIBL;
	}

	o_color = vec4(directLighting + ambientLighting, 1.0);
}