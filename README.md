# simp_gpu

Refreshingly simple graphics API

Ideas based on this [blog](https://www.sebastianaaltonen.com/blog/no-graphics-api)


Assumptions that we make which allow the API to be simple:
- Bindless textures
- Buffer device address
- Most CPU-visible memory is host coherent uncached memory.
- All resources are concurrent between all queues.
- texture layout GENERAL. (see VK_KHR_unified_layouts).
- 