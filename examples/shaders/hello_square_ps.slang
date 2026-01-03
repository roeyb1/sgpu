import "common";

struct PS_Input {
    float3 color: COLOR;
}

[vk::push_constant]
PixelParams<float3> color;

[shader("pixel")]
float4 main(PS_Input input) : SV_Target0 {
    // can either fetch the color from the shader inputs or from the vertex colors.
    //return float4(color.get(), 1.);
    return float4(input.color, 1.);
}