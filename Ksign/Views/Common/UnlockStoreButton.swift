//
//  UnlockStoreButton.swift
//  Ksign
//
//  Toolbar button with an unlock symbol. It only opens the ARM Store web page.
//

import SwiftUI
import NimbleViews

struct UnlockStoreButton: View {
	static let storeURL = URL(string: "https://armconverter.com/store/us")!
	
	@State private var _isPresenting = false
	
	var body: some View {
		Button {
			_isPresenting = true
		} label: {
			Image(systemName: "lock.open")
		}
		.sheet(isPresented: $_isPresenting) {
			SafariRepresentableView(url: Self.storeURL).ignoresSafeArea()
		}
	}
}
