import common;


[[vk::push_constant]]
ComputeParams<float> params;

[shader("compute")]
[numthreads(64)]
void main(uint index: SV_DispatchThreadID) {
    float* p = params.ptr();

    // really boring shader which just sets the values of the buffer.
    p[index] = 1.0;
}
