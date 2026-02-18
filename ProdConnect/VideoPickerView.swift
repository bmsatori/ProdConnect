//
//  VideoPickerView.swift
//  ProdConnect
//
//  Created by Benjy Satorius on 10/26/25.
//


import SwiftUI
import PhotosUI

struct VideoPickerView: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPickerView
        init(_ parent: VideoPickerView) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier("public.movie") else { return }
            
            provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
                DispatchQueue.main.async {
                    self.parent.selectedURL = url
                }
            }
        }
    }
}
