import Foundation
import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0.0
    @State private var heartBeat: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0
    @State private var loadingDots: String = ""
    @State private var backgroundGradientOffset: CGFloat = 0

    // Choose between "splash_logo" or "splash1_logo"
    private let selectedLogo = "splash_logo"

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color.blue.opacity(0.3),
                    Color.red.opacity(0.2),
                    Color.black,
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .hueRotation(.degrees(backgroundGradientOffset))
            .ignoresSafeArea()

            // Pulse rings behind logo
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.red.opacity(0.6),
                                Color.pink.opacity(0.3),
                                Color.clear,
                            ]),
                            startPoint: .center,
                            endPoint: .trailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 200 + CGFloat(index * 40), height: 200 + CGFloat(index * 40))
                    .scaleEffect(heartBeat)
                    .opacity(pulseOpacity * (1.0 - Double(index) * 0.3))
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: heartBeat
                    )
            }

            VStack(spacing: 40) {
                // Logo with heart animation
                VStack(spacing: 20) {
                    // Main logo (dynamically selected)
                    Image(selectedLogo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 150, height: 150)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .shadow(color: .red.opacity(0.5), radius: 20, x: 0, y: 0)

                    // App title with elegant typography
                    VStack(spacing: 8) {
                        Text("HeartScanner")
                            .font(.system(size: 32, weight: .light, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [.white, .red.opacity(0.8)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .opacity(logoOpacity)

                        Text("Clinical AI Cardiac Analysis")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .opacity(logoOpacity)
                    }
                }

                // Modern loading indicator
                VStack(spacing: 16) {
                    // Heartbeat loading animation
//                    HStack(spacing: 8) {
//                        ForEach(0..<3, id: \.self) { index in
//                            Circle()
//                                .fill(
//                                    LinearGradient(
//                                        gradient: Gradient(colors: [.red, .pink]),
//                                        startPoint: .top,
//                                        endPoint: .bottom
//                                    )
//                                )
//                                .frame(width: 12, height: 12)
//                                .scaleEffect(heartBeat)
//                                .opacity(pulseOpacity)
//                                .animation(
//                                    Animation.easeInOut(duration: 0.8)
//                                        .repeatForever(autoreverses: true)
//                                        .delay(Double(index) * 0.2),
//                                    value: heartBeat
//                                )
//                        }
//                    }

                    // Loading text with animated dots
                    VStack(spacing: 8) {
                        Text("Initializing Clinical Models\(loadingDots)")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .opacity(logoOpacity)
                    }
                }
                .padding(.top, 20)
            }

            // Floating heart particles
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: "heart.fill")
                    .foregroundColor(.red.opacity(0.3))
                    .font(.system(size: CGFloat.random(in: 8...16)))
                    .position(
                        x: CGFloat.random(in: 50...350),
                        y: CGFloat.random(in: 100...700)
                    )
                    .opacity(pulseOpacity * 0.5)
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 2...4))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.5),
                        value: pulseOpacity
                    )
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Logo entrance animation
        withAnimation(.easeOut(duration: 1.0)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }

        // Start heartbeat animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                heartBeat = 1.2
                pulseOpacity = 1.0
            }
        }

        // Background gradient animation
        withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            backgroundGradientOffset = 360
        }

        // Animated loading dots
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            withAnimation(.easeInOut(duration: 0.3)) {
                if loadingDots.count < 3 {
                    loadingDots += "."
                } else {
                    loadingDots = ""
                }
            }
        }
    }
}

#Preview {
    SplashView()
        .preferredColorScheme(.dark)
}
