import SwiftUI
import AudioToolbox
import CoreLocation

/// Full-screen overlay displayed when a crash is detected.
struct CrashAlertView: View {
    @ObservedObject var crashDetector: CrashDetector
    var location: CLLocation? = nil
    @EnvironmentObject var locationManager: LocationManager

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Pulsing red/orange background
            RadialGradient(
                colors: [.red, .orange.opacity(0.8)],
                center: .center,
                startRadius: 50,
                endRadius: 500
            )
            .scaleEffect(pulseScale)
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .shadow(radius: 4)

                Text("Crash Detected")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                // Countdown
                Text("\(crashDetector.countdownSeconds)")
                    .font(.system(size: 100, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: crashDetector.countdownSeconds)

                Text(crashDetector.isTestMode
                     ? "Test alert — no message will be sent"
                     : "Sending alert in \(crashDetector.countdownSeconds) seconds…")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))

                // Emergency contact names
                let contacts = CrashDetector.loadEmergencyContacts()
                if !contacts.isEmpty && !crashDetector.isTestMode {
                    VStack(spacing: 4) {
                        Text("Alerting:")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        ForEach(contacts) { contact in
                            Text(contact.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                        }
                    }
                }

                Spacer()

                // Large "I'm OK" dismiss button
                Button {
                    crashDetector.dismissCrashAlert()
                } label: {
                    Text("I'm OK")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            startPulseAnimation()
            AudioServicesPlayAlertSound(SystemSoundID(1005))  // system alert
        }
        .onChange(of: crashDetector.countdownSeconds) { _, newValue in
            if newValue <= 0, !crashDetector.isTestMode {
                crashDetector.sendEmergencyAlert(location: location ?? locationManager.currentLocation)
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }
}
