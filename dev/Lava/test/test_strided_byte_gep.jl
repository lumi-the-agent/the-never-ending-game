# A tuple captured in a closure and read in a loop LLVM kept rolled: the closure is copied into a
# private alloca and element k is read by BYTE offset, `gep i8, ptr %alloca, (24 * %k + C)`.
# lift_byte_geps_on_allocas! lifted only constant offsets, so this one reached SPIR-V untyped and
# every element read as element 0 (WaterLily's measure! on Mantle saw only the first of ten fence
# slats, 2026-11-28). The layout is the one from that kernel: { float, i64, { { float,
# [10 x [2 x [1 x [3 x float]]]] } }, float } in a one-element wrapper; the array starts at byte 20.
using LLVM, Lava, Test

@testset "strided byte GEP into a private array is lifted" begin
    LLVM.Context() do _
        # Lava's layout (i64 aligned to 8): the array sits at byte 20, as in the kernel. LLVM's
        # default layout aligns i64 to 4 and would move it to 16.
        mod = parse(LLVM.Module, """
            target datalayout = "e-i64:64-i128:128-v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-n8:16:32:64-G1"
            target triple = "spirv64-unknown-unknown-unknown"
            @out = internal addrspace(3) global [64 x float] undef
            define void @main(float %seed) {
            entry:
              %clo = alloca { [1 x { float, i64, { { float, [10 x [2 x [1 x [3 x float]]]] } }, float }] }, align 8
              %first = getelementptr { [1 x { float, i64, { { float, [10 x [2 x [1 x [3 x float]]]] } }, float }] }, ptr %clo, i32 0, i32 0, i64 0, i32 2, i32 0, i32 1, i64 3, i64 1, i64 0, i64 2
              store float %seed, ptr %first
              br label %loop
            loop:
              %k = phi i64 [ 1, %entry ], [ %next, %loop ]
              %acc = phi float [ 0.0, %entry ], [ %sum, %loop ]
              %o = mul i64 %k, 24
              %oc = add i64 %o, -4
              %pc = getelementptr i8, ptr %clo, i64 %oc
              %c1 = load float, ptr %pc
              %oh = or disjoint i64 %o, 4
              %ph = getelementptr i8, ptr %clo, i64 %oh
              %h2 = load float, ptr %ph
              %o16 = add i64 %o, 16
              %p16 = getelementptr i8, ptr %clo, i64 %o16
              %h3 = load float, ptr %p16
              %s1 = fadd float %c1, %h2
              %s2 = fadd float %s1, %h3
              %sum = fadd float %acc, %s2
              %next = add i64 %k, 1
              %done = icmp eq i64 %next, 11
              br i1 %done, label %exit, label %loop
            exit:
              %out0 = getelementptr [64 x float], ptr addrspace(3) @out, i64 0, i64 0
              store float %sum, ptr addrspace(3) %out0
              ret void
            }
            """)
        @test LLVM.verify(mod) === nothing
        Lava.lift_strided_byte_geps!(mod)
        @test LLVM.verify(mod) === nothing
        f = LLVM.functions(mod)["main"]
        geps = [i for b in LLVM.blocks(f) for i in LLVM.instructions(b) if i isa LLVM.GetElementPtrInst]
        # no byte GEP is left on the alloca
        @test !any(g -> LLVM.LLVMType(LLVM.API.LLVMGetGEPSourceElementType(g)) == LLVM.Int8Type(), geps)
        lifted = filter(g -> startswith(LLVM.name(g), "typed_gep_strided"), geps)
        @test length(lifted) == 3
        consts(g) = [o isa LLVM.ConstantInt ? convert(Int, o) : :dyn for o in LLVM.operands(g)[2:end]]
        # element k - 1 (C = -4 and 0 are both in element k - 1: byte 20 + 24 (k - 1)), then the leaf
        @test sort(consts.(lifted)) == sort([
            [0, 0, 0, 2, 0, 1, :dyn, 0, 0, 0],   # 24k - 4  -> [k-1][0][0][0]
            [0, 0, 0, 2, 0, 1, :dyn, 0, 0, 2],   # 24k + 4  -> [k-1][0][0][2]
            [0, 0, 0, 2, 0, 1, :dyn, 1, 0, 2]])  # 24k + 16 -> [k-1][1][0][2]
        # the dynamic index is k - 1 (operand 1 is the pointer, the 7th index is the 8th operand)
        for g in lifted
            i = LLVM.operands(g)[8]
            @test i isa LLVM.Instruction && LLVM.opcode(i) == LLVM.API.LLVMAdd
            @test convert(Int, LLVM.operands(i)[2]) == -1
        end
        bytes, _ = Lava.emit_spirv_from_llvm(mod, "main", (64, 1, 1))
        @test Lava.validate_spirv(bytes) === nothing
    end
end
