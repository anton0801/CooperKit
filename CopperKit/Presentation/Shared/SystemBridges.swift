import SwiftUI
import PhotosUI
import AVFoundation

/// The system photo picker (no library permission needed). Returns downscaled JPEG data.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let limit: Int
    let onPick: ([Data]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = max(1, limit)
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([Data]) -> Void

        init(onPick: @escaping ([Data]) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let providers = results.map(\.itemProvider).filter { $0.canLoadObject(ofClass: UIImage.self) }
            guard !providers.isEmpty else { return }
            let group = DispatchGroup()
            var images = [Int: Data]()
            let lock = NSLock()
            for (index, provider) in providers.enumerated() {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage, let data = ImageShrinker.jpeg(image) {
                        lock.lock(); images[index] = data; lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { [onPick] in
                onPick(images.keys.sorted().compactMap { images[$0] })
            }
        }
    }
}

/// The camera, for photographing a tool on the bench.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    @Environment(\.presentationMode) private var presentationMode

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    static var isDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = ImageShrinker.jpeg(image) {
                parent.onPick(data)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

/// Re-encodes a photo at a sensible size; metadata (including location) is dropped.
enum ImageShrinker {
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }
}

/// The system share sheet, opened only when the owner asks.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A shareable payload for `.sheet(item:)`.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Writes text to a temporary file so it can be shared as a document.
enum TemporaryExport {
    static func file(named name: String, contents: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CopperKitExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        do {
            try contents.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// A tool's photo from the photo store, or its drawn category icon.
struct ToolThumbnail: View {
    @EnvironmentObject private var store: WorkshopStore
    let tool: Tool?
    var size: CGFloat = CK.Size.thumb

    var body: some View {
        Group {
            if let id = tool?.photoIDs.first, let data = store.photos.load(id), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    CK.Palette.velvet
                    Image(systemName: tool?.category.icon ?? "questionmark")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(CK.Palette.gold)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: CK.Radius.thumb, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CK.Radius.thumb, style: .continuous)
                .strokeBorder(CK.Palette.copper.opacity(0.35), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

/// Small floating confirmation at the bottom of the screen.
struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: CK.Space.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(CK.Palette.gold)
            Text(text)
                .font(CKFont.subhead.weight(.semibold))
                .foregroundColor(CK.Palette.cream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CK.Space.m)
        .padding(.vertical, CK.Space.s)
        .background(Capsule().fill(CK.Palette.deepBlue))
        .overlay(Capsule().strokeBorder(CK.Palette.copper.opacity(0.6), lineWidth: 1))
        .shadow(color: CK.Palette.deepBlue.opacity(0.25), radius: 10, y: 4)
        .padding(.horizontal, CK.Space.m)
        .accessibilityHidden(true)
    }
}
