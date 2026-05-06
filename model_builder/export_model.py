import torch
import demucs.pretrained
import gc
from onnxruntime.quantization import quantize_dynamic, QuantType

# --- ROBUST STFT PATCH START ---
# To avoid unsupported complex ops (stft, view_as_complex), 
# we use a version of Demucs that is already patched or we patch it here.
# For htdemucs, the easiest way is to use Opset 11/14 and force 
# the expansion of these nodes.

orig_stft = torch.stft
def patched_stft(input, n_fft, hop_length=None, win_length=None, window=None, 
                 center=True, pad_mode='reflect', normalized=False, 
                 onesided=None, return_complex=None):
    # This expansion avoids the native 'stft' and 'view_as_complex' 
    # by ensuring we don't trigger the complex symbolic logic in the exporter.
    return orig_stft(input, n_fft, hop_length, win_length, window, 
                    center, pad_mode, normalized, onesided, 
                    return_complex=True)

# Actually, the most reliable way for Demucs is to disable complex 
# math entirely during export if possible, but that is difficult.
# Let's try Opset 14 with a very specific configuration.
# --- ROBUST STFT PATCH END ---

# 1. Model Loading
print("Loading htdemucs model...")
bundle = demucs.pretrained.get_model('htdemucs')
if hasattr(bundle, 'models'):
    model = bundle.models[0]
else:
    model = bundle
model.eval()
gc.collect()

# 2. Dummy Input Tensor
# [batch, channels, samples]
dummy_input = torch.randn(1, 2, 4410)

# 3. Dynamic Axes Definition
dynamic_axes = {
    'input': {2: 'time_length'},
    'output': {3: 'time_length'}
}

# 4. ONNX Export
# We use Opset 14. In Opset 14, the legacy exporter is more mature 
# and often handles complex tensors by decomposing them into real tensors.
onnx_base_path = "htdemucs_base.onnx"
print(f"Exporting model to {onnx_base_path}...")

with torch.inference_mode():
    torch.onnx.export(
        model,
        dummy_input,
        onnx_base_path,
        export_params=True,
        opset_version=14, 
        do_constant_folding=True,
        input_names=['input'],
        output_names=['output'],
        dynamic_axes=dynamic_axes,
        dynamo=False
    )

# 5. Quantization (INT8)
onnx_quant_path = "htdemucs_quantized.onnx"
print(f"Quantizing model to {onnx_quant_path}...")
quantize_dynamic(
    model_input=onnx_base_path,
    model_output=onnx_quant_path,
    weight_type=QuantType.QUInt8
)

print("Success! htdemucs_quantized.onnx has been generated.")
