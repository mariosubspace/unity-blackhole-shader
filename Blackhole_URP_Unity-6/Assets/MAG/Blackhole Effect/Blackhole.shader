Shader "MAG/Blackhole"
{
    Properties
    {
        // Strength of both the distortion and hole size.
        // Useful if wanting to animate the blackhole appearing.
        _GlobalStrength ("Global Strength", Range(0, 1)) = 1

        // Distortion amount around black hole.
        _DistortionStrength ("Distortion Strength", Range(0, 3)) = 1.5

        // Hole size is separate from distortion for artistic flexibility.
        _HoleSize ("Hole Size", Range(0, 1)) = 0.2

        // 0 is no smoothness at all, will be jagged.
        // 1 is exact anti-aliased smoothing based on screen derivative.
        // Higher values are even softer.
        // Use what you like, but recommended is 1.0 or 1.5.
        // Adjust in the material inspector not here.
        _HoleEdgeSmoothness ("Hole Edge Smoothness", Range(0, 10)) = 4
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            ZWrite Off
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Note: this will not capture transparent objects in the scene.
            // Make sure "Opaque Texture" is enabled in your URP Pipeline Asset. 
            sampler2D _CameraOpaqueTexture;

            CBUFFER_START(UnityPerMaterial)
            float _GlobalStrength;
            float _DistortionStrength;
            float _HoleSize;
            float _HoleEdgeSmoothness;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 positionNDC : TEXCOORD2;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz); 

                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS.xyz);

                // NDC/Screen-relative coords.
                OUT.positionNDC = ComputeNormalizedDeviceCoordinates(IN.positionOS.xyz, UNITY_MATRIX_MVP);

                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                // Renormalize because interpolation may alter length.
                float3 normalWS = normalize(IN.normalWS);

                // Note: _WorldSpaceCameraPos is set by legacy code, this may break
                // whenever Unity decides to update that. It seems this is still what they're using too.
                float3 viewDirectionWS = normalize(_WorldSpaceCameraPos.xyz - IN.positionWS);

                // Remap from [0, 1] to [1, 0];
                float invertedHoleSize = 1.0 - _HoleSize * _GlobalStrength;

                // 1 when normal is toward camera, 0 when normal is perpendicular or behind object.
                float NdotVSat = max(0, dot(normalWS, viewDirectionWS));
                // Fresnel mask goes from 0 to 1 at the edges of the object.
                float fresnelMask = 1.0 - NdotVSat;

                // Calculate screen-space derivative for anti-aliasing the hole edge.
                float NDotVSatDeriv = length(float2(abs(ddx(NdotVSat)), abs(ddy(NdotVSat))));

                float holeMask = 1.0 - smoothstep( 
                        invertedHoleSize, 
                        invertedHoleSize + NDotVSatDeriv * _HoleEdgeSmoothness, 
                        NdotVSat );

                // Note: abs is not really necessary here, added to silence a warning.
                // Base distortion goes from max distortion at the center to no distortion at the edges.
                // We use Fresnel, then invert, because that results in a better looking falloff in the end than
                // just using NdotVSat and not inverting, something to do with floating point math.
                // At this step though the edge is harsh.
                float distortionAmount = 1.0 - pow(abs(fresnelMask), _DistortionStrength * _GlobalStrength);
                // Raise distortion amount to a higher power which pushes the distortion more in the center
                // and more smoothly fades the outside toward non-distortion.
                // 4 seems too little, 8 too much, 6 seems better; in my opinion.
                // Not exposed as a parameter because I don't think that's needed and it becomes more confusing to tweak.
                distortionAmount = pow(distortionAmount, 6.0);

                // Remap screen coords from [0, 1] to [1, -1] to create max distortion offset direction.
                float2 positionNDCRemapped = -2 * IN.positionNDC + 1;
                // Smaller distortion amount is smaller distortion offset.
                float2 uvDistortionOffset = distortionAmount * positionNDCRemapped;
                // Offset screen coords towards the distortion offset. Max distortion will result in a flipped image.
                float2 distortedUVs = uvDistortionOffset + IN.positionNDC;

                // Get rendered background scene texture using distorted UVs.
                float3 distortedBackground = tex2D(_CameraOpaqueTexture, distortedUVs).rgb;

                // Use hole mask to black out hole part by multiplying with distorted color.
                // Return final color.
                return float4((holeMask * distortedBackground).rgb, 1);
            }

            ENDHLSL
        }
    }
}
