Shader "Custom/MyPBL"
{
	Properties
	{
		_Color ("Main Color", Color) = (1,1,1,1)
		_SpecularColor ("Specular Color", Color) = (1,1,1,1)
		_Glossiness ("Smoothness", Range(0,1)) = 1
		_Metallic ("Metalness", Range(0,1)) = 0

		_Anisotropic("Anisotropic", Range(-20, 1)) = 0
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" "Queue"="Geometry" }

		Pass {
			Name "FORWARD"
			Tags { "LightMode"="ForwardBase" }
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#define UNITY_PASS_ForwardBase
			#include "UnityCG.cginc"
			#include "AutoLight.cginc"
			#include "Lighting.cginc"
			#pragma multi_compile_fwdbase-fullshadows
			#pragma target 3.0

			float4 _Color;
			float4 _SpecularColor;
			float _Glossiness;
			float _Metallic;
			
			float _Anisotropic;

			//NDF functions
			float BlinnPhongNormalDistribution(float NdotH,
				 							   float specularpower,
											   float speculargloss) {
				float Distribution = pow(NdotH, speculargloss) * specularpower;
				Distribution *= (2 + specularpower) / (2 * 3.1415926535);
				return Distribution;
			}

			float PhongNormalDistribution(float RdotV, 
										  float specularpower, 
										  float speculargloss) {
				float Distribution = pow(RdotV, speculargloss) * specularpower;
				Distribution *= (2 + specularpower) / (2 * 3.1415926535);
				return Distribution;
			}

			float BeckmanNormalDistribution(float roughness, float NdotH) {
				float roughnessSqr = roughness * roughness;
				float NdotHSqr = NdotH * NdotH;
				return max(0.000001, 
					(1.0 / (3.1415926535 * roughnessSqr * NdotHSqr * NdotHSqr)) *
					exp((NdotHSqr - 1) / (roughnessSqr * NdotHSqr)));
			}

			float GaussianNormalDistribution(float roughness, float NdotH) {
				float roughnessSqr = roughness * roughness;
				float thetaH = acos(NdotH);
				return exp(-thetaH * thetaH / roughnessSqr);
			}

			float GGXNormalDistribution(float roughness, float NdotH) {
				float roughnessSqr = roughness * roughness;
				float NdotHSqr = NdotH * NdotH;
				float TanNdotHSqr = (1 - NdotHSqr) / NdotHSqr;
				float NDFRoot = 
					(roughness / (NdotHSqr * (roughnessSqr + TanNdotHSqr)));
				return (1.0 / 3.1415926535) * NDFRoot * NDFRoot;
			}

			float TrowbridgeReitzNormalDistribution(float NdotH, float roughness) {
				float roughnessSqr = roughness * roughness;
				float Distribution = NdotH * NdotH * (roughnessSqr - 1.0) + 1.0;
				return roughnessSqr / (3.1415926535 * Distribution * Distribution);
			}

			float TrowbridgeReitzAnistropicNormalDistribution(float anisotropic, 
															 float NdotH, 
															 float HdotX, 
															 float HdotY){
				float aspect = sqrt(1.0h - anisotropic * 0.9h);
				float X = max(.001, 
					(1.0 - _Glossiness) * (1.0 - _Glossiness) / aspect) * 5;
				float Y = max(.001, 
					(1.0 - _Glossiness) * (1.0 - _Glossiness) * aspect) * 5;
				return 1.0 / (3.1415926535 * X * Y * 
					((HdotX / X) * (HdotX / X) + 
					 (HdotY / Y) * (HdotY / Y) + 
					 NdotH * NdotH) * 
					((HdotX / X) * (HdotX / X) + 
					 (HdotY / Y) * (HdotY / Y) + 
					 NdotH * NdotH));
			}

			float WardAnisotropicNormalDistribution(float anisotropic,
													float NdotL,
													float NdotV,
													float NdotH,
													float HdotX,
													float HdotY) {
				float aspect = sqrt(1.0h - anisotropic * 0.9h);
				float X = max(.001, 
					(1.0 - _Glossiness) * (1.0 - _Glossiness) / aspect) * 5;
				float Y = max(.001,
					(1.0 - _Glossiness) * (1.0 - _Glossiness) * aspect) * 5;
				float exponent = -((HdotX / X) * (HdotX / X) + 
					(HdotY / Y) * (HdotY / Y)) / (NdotH * NdotH);
				float Distribution = 1.0 / 
					(4.0 * 3.14159265 * X * Y * sqrt(NdotL * NdotV));
				Distribution *= exp(exponent);
				return Distribution;
			}

			//GSF functions

			struct VertexInput {
				float4 vertex : POSITION;		//local vertex position
				float3 normal : NORMAL;			//normal direction
				float4 tangent : TANGENT;		//tangent direction
				float2 texcoord0 : TEXCOORD0;	//uv coordinates
				float2 texcoord1 : TEXCOORD1;	//lightmap uv coordinates
			};

			struct VertexOutput {
				float4 pos : SV_POSITION;	//screen clip space position and depth
				float2 uv0 : TEXCOORD0;		//uv coordinates
				float2 uv1 : TEXCOORD1;		//lightmap uv coordinates
				
				//below create our own variables with the texcoord semantic
				float3 normalDir : TEXCOORD3;	//normal direction
				float3 posWorld : TEXCOORD4;	//normal direction
				float3 tangentDir : TEXCOORD5;	
				float3 bitangentDir : TEXCOORD6;

				//this initializes the unity lighting and shadow
				LIGHTING_COORDS(7, 8)
				//this initializes the unity fog
				UNITY_FOG_COORDS(9)
			};

			VertexOutput vert(VertexInput v) {
				VertexOutput o = (VertexOutput)0;
				o.uv0 = v.texcoord0;
				o.uv1 = v.texcoord1;
				o.normalDir = UnityObjectToWorldNormal(v.normal);
				o.tangentDir = normalize(
					mul(unity_ObjectToWorld, float4(v.tangent.xyz,0.0)).xyz);
				o.bitangentDir = normalize(
					cross(o.normalDir, o.tangentDir) * v.tangent.w);
				o.pos = UnityObjectToClipPos(v.vertex);
				o.posWorld = mul(unity_ObjectToWorld, v.vertex);
				UNITY_TRANSFER_FOG(o, o.pos);
				TRANSFER_VERTEX_TO_FRAGMENT(o);
				return o;
			}

			float4 frag(VertexOutput i) : COLOR {
				//normal direction calculations
				float3 normalDirection = normalize(i.normalDir);
				float3 lightDirection = normalize(lerp(
					_WorldSpaceLightPos0.xyz,
					_WorldSpaceLightPos0.xyz - i.posWorld.xyz,
					_WorldSpaceLightPos0.w));
				float3 lightReflectDirection = 
					reflect(-lightDirection, normalDirection);
				float3 viewDirection =
					normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);
				float3 viewReflectDirection =
					normalize(reflect(-viewDirection, normalDirection));
				float3 halfDirection = normalize(viewDirection + lightDirection);

				float NdotL = max(0.0, dot(normalDirection, lightDirection));
				float NdotH = max(0.0, dot(normalDirection, halfDirection));
				float NdotV = max(0.0, dot(normalDirection, viewDirection));
				float VdotH = max(0.0, dot(viewDirection, halfDirection));
				float LdotH = max(0.0, dot(lightDirection, halfDirection));
				float LdotV = max(0.0, dot(lightDirection, viewDirection));
				float RdotV = max(0.0, dot(lightReflectDirection, viewDirection));
				float attenuation = LIGHT_ATTENUATION(i);
				float3 attenColor = attenuation * _LightColor0.rgb;

				//Roughness
				//1 - smoothness * smoothness
				float roughness = 1 - (_Glossiness * _Glossiness);
				roughness - roughness * roughness;

				//Metallic
				float3 diffuseColor = _Color.rgb * (1 - _Metallic);
				float3 specColor = 
					lerp(_SpecularColor.rgb, _Color.rgb, _Metallic * 0.5);
				
				// float3 SpecularDistribution = specColor;

				//Blinn-Phong NDF
				// SpecularDistribution *= BlinnPhongNormalDistribution(
				// 	NdotH, _Glossiness, max(1, _Glossiness * 40));
					
				//Phong NDF
				// SpecularDistribution *= PhongNormalDistribution(
				// 	RdotV, _Glossiness, max(1, _Glossiness * 40));

				//Bechman NDF
				// SpecularDistribution *= 
				// 	BeckmanNormalDistribution(roughness, NdotH);

				//Gaussian NDF
				// SpecularDistribution *= 
				// 	GaussianNormalDistribution(roughness, NdotH);

				//GGX NDF
				// SpecularDistribution *= GGXNormalDistribution(roughness, NdotH);

				//Trowbridge-Reitz NDF
				// SpecularDistribution *= 
				// 	TrowbridgeReitzNormalDistribution(NdotH, roughness);

				//Trowbridge-Reitz Anisotropic NDF
				// SpecularDistribution *= 
				// 	TrowbridgeReitzAnistropicNormalDistribution(
				// 		_Anisotropic,
				// 		NdotH, 
				// 		dot(halfDirection, i.tangentDir),
				// 		dot(halfDirection, i.bitangentDir));

				//Ward Anisotropic NDF
				// SpecularDistribution *= 
				// 	WardAnisotropicNormalDistribution(
				// 		_Anisotropic,
				// 		NdotL,
				// 		NdotV,
				// 		NdotH,
				// 		dot(halfDirection, i.tangentDir),
				// 		dot(halfDirection, i.bitangentDir));

				// return float4(float3(1, 1, 1) * SpecularDistribution.rgb, 1);

				float GeometricShadow = 1;

				return float4(float3(1, 1, 1) * GeometricShadow, 1);
			}

			ENDCG
		}
	}
	FallBack "Legacy Shaders/Diffuse"
}
