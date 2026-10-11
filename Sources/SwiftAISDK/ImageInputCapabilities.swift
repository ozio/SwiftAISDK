// Model capabilities from the published upstream packages. Unknown IDs remain nil.

public extension AmazonBedrockImageModel {
    var supportsFileInputs: Bool? {
        if ["amazon.nova-canvas-v1:0"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        supportsFileInputs
    }
}

public extension BlackForestLabsImageModel {
    var supportsFileInputs: Bool? {
        if ["flux-kontext-pro", "flux-kontext-max", "flux-pro-1.0-fill", "flux-3-image"].contains(modelID) { return true }
        if ["flux-pro-1.1-ultra", "flux-pro-1.1"].contains(modelID) { return false }
        return nil
    }

    var supportsMaskInputs: Bool? {
        if ["flux-pro-1.0-fill"].contains(modelID) { return true }
        return supportsFileInputs == nil ? nil : false
    }
}

public extension DeepInfraImageModel {
    var supportsFileInputs: Bool? {
        if ["stabilityai/sd3.5", "black-forest-labs/FLUX-1.1-pro", "black-forest-labs/FLUX-1-schnell", "black-forest-labs/FLUX-1-dev", "black-forest-labs/FLUX-pro", "black-forest-labs/FLUX.1-Kontext-dev", "black-forest-labs/FLUX.1-Kontext-pro", "Qwen/Qwen-Image-Edit", "stabilityai/sd3.5-medium", "stabilityai/sdxl-turbo"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        supportsFileInputs
    }
}

public extension FalImageModel {
    var supportsFileInputs: Bool? {
        if ["fal-ai/flux-2/edit", "fal-ai/flux-pro/kontext", "fal-ai/flux-pro/kontext/max", "fal-ai/flux-general/image-to-image", "fal-ai/flux-general/inpainting", "fal-ai/flux-lora/image-to-image", "fal-ai/flux-lora/inpainting", "fal-ai/flux/dev/image-to-image", "fal-ai/flux/krea/image-to-image", "fal-ai/recraft/v3/image-to-image"].contains(modelID) { return true }
        if ["bria/text-to-image/3.2", "fal-ai/bria/text-to-image/base", "fal-ai/bria/text-to-image/fast", "fal-ai/bria/text-to-image/hd", "fal-ai/bytedance/dreamina/v3.1/text-to-image", "fal-ai/flux-kontext-lora/text-to-image", "fal-ai/recraft/v3/text-to-image", "fal-ai/wan/v2.2-5b/text-to-image", "fal-ai/wan/v2.2-a14b/text-to-image"].contains(modelID) { return false }
        return nil
    }

    var supportsMaskInputs: Bool? {
        if ["fal-ai/flux-general/inpainting", "fal-ai/flux-lora/inpainting"].contains(modelID) { return true }
        return supportsFileInputs == nil ? nil : false
    }
}

public extension FireworksImageModel {
    var supportsFileInputs: Bool? {
        if ["accounts/fireworks/models/flux-kontext-pro", "accounts/fireworks/models/flux-kontext-max"].contains(modelID) { return true }
        if ["accounts/fireworks/models/flux-1-dev-fp8", "accounts/fireworks/models/flux-1-schnell-fp8", "accounts/fireworks/models/playground-v2-5-1024px-aesthetic", "accounts/fireworks/models/japanese-stable-diffusion-xl", "accounts/fireworks/models/playground-v2-1024px-aesthetic", "accounts/fireworks/models/SSD-1B", "accounts/fireworks/models/stable-diffusion-xl-1024-v1-0"].contains(modelID) { return false }
        return nil
    }

    var supportsMaskInputs: Bool? {
        return supportsFileInputs == nil ? nil : false
    }
}

public extension LumaImageModel {
    var supportsFileInputs: Bool? {
        if ["photon-1", "photon-flash-1"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        return supportsFileInputs == nil ? nil : false
    }
}

public extension QuiverAIImageModel {
    var supportsFileInputs: Bool? {
        if ["arrow-1", "arrow-1.1", "arrow-1.1-max", "arrow-2", "arrow-2-telos"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        return supportsFileInputs == nil ? nil : false
    }
}

public extension ReplicateImageModel {
    var supportsFileInputs: Bool? {
        if ["black-forest-labs/flux-2-pro", "black-forest-labs/flux-2-dev", "black-forest-labs/flux-fill-pro", "black-forest-labs/flux-fill-dev"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        if ["black-forest-labs/flux-fill-pro", "black-forest-labs/flux-fill-dev"].contains(modelID) { return true }
        return supportsFileInputs == nil ? nil : false
    }
}

public extension TogetherAIImageModel {
    var supportsFileInputs: Bool? {
        if ["black-forest-labs/FLUX.1-kontext-pro", "black-forest-labs/FLUX.1-kontext-max", "black-forest-labs/FLUX.1-kontext-dev", "black-forest-labs/FLUX.1-canny", "black-forest-labs/FLUX.1-depth", "black-forest-labs/FLUX.1-redux", "black-forest-labs/FLUX.2-pro", "black-forest-labs/FLUX.2-flex"].contains(modelID) { return true }
        if ["stabilityai/stable-diffusion-xl-base-1.0", "black-forest-labs/FLUX.1-dev", "black-forest-labs/FLUX.1-dev-lora", "black-forest-labs/FLUX.1-schnell", "black-forest-labs/FLUX.1.1-pro", "black-forest-labs/FLUX.1-pro", "black-forest-labs/FLUX.1-schnell-Free", "black-forest-labs/FLUX.2-dev", "google/gemini-3-pro-image"].contains(modelID) { return false }
        return nil
    }

    var supportsMaskInputs: Bool? {
        return supportsFileInputs == nil ? nil : false
    }
}

public extension XAIImageModel {
    var supportsFileInputs: Bool? {
        if ["grok-imagine-image", "grok-imagine-image-pro", "grok-imagine-image-2.0"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        return supportsFileInputs == nil ? nil : false
    }
}

public extension GoogleImageGenerationModel {
    var supportsFileInputs: Bool? {
        if ["gemini-2.5-flash-image", "gemini-3-pro-image-preview", "gemini-3.1-flash-image-preview"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        return supportsFileInputs == nil ? nil : false
    }
}

public extension GoogleVertexImageModel {
    var supportsFileInputs: Bool? {
        if ["gemini-2.5-flash-image", "gemini-3-pro-image-preview", "gemini-3.1-flash-image-preview"].contains(modelID) { return true }
        return nil
    }

    var supportsMaskInputs: Bool? {
        return supportsFileInputs == nil ? nil : false
    }
}

public extension OpenAICompatibleImageModel {
    var supportsFileInputs: Bool? {
        guard hasOpenAIImageCapabilities else { return nil }
        if ["dall-e-2", "gpt-image-1", "gpt-image-1-mini", "gpt-image-1.5", "gpt-image-2", "gpt-image-2.5-flare", "gpt-image-2.5-flare-2026-09-08", "gpt-image-2.5-sunburst", "gpt-image-2.5-sunburst-2026-09-08", "chatgpt-image-latest"].contains(modelID) { return true }
        if ["dall-e-3"].contains(modelID) { return false }
        return nil
    }

    var supportsMaskInputs: Bool? {
        supportsFileInputs
    }
}

public extension ProdiaImageModel {
    var supportsFileInputs: Bool? { false }
    var supportsMaskInputs: Bool? { false }
}
