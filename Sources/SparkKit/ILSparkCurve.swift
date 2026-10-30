import Accelerate
import Foundation

/// Smooth curves through sampled spectrum values, for pulsar plots of channel and spectrum analyzer data
public enum ILSparkCurve {

    /// @returns a smooth curve through the values, `factor` points for each value
    ///
    /// the values are extended with their mirror image so the ends meet, transformed with an FFT, then the spectrum is
    /// zero padded and tapered and transformed back, which interpolates the values with a band limited curve
    public static func curve(_ values: [Double], factor: Int = 8) -> [Double] {
        guard values.count > 1, factor > 1 else { return values }

        let mirrored = values + values.reversed() // periodic, without a jump at the ends
        let count = mirrored.count
        let log2n = vDSP_Length(ceil(log2(Double(count))))
        let length = 1 << Int(log2n)
        let upLog2n = log2n + vDSP_Length(ceil(log2(Double(factor))))
        let upLength = 1 << Int(upLog2n)

        guard let setup = vDSP_create_fftsetupD(upLog2n, FFTRadix(kFFTRadix2)) else { return values }
        defer { vDSP_destroy_fftsetupD(setup) }

        // resample the mirrored values to the power of two length, linearly
        var samples = [Double](repeating: 0, count: length)
        for index in 0..<length {
            let position = Double(index) * Double(count) / Double(length)
            let lower = Int(position) % count, upper = (Int(position) + 1) % count
            let fraction = position - floor(position)
            samples[index] = mirrored[lower] * (1 - fraction) + mirrored[upper] * fraction
        }

        // forward transform, in split complex form, taper, then the inverse transform at the longer length
        var real = [Double](repeating: 0, count: upLength / 2)
        var imaginary = [Double](repeating: 0, count: upLength / 2)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPDoubleSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                samples.withUnsafeBufferPointer { sampleBuffer in
                    sampleBuffer.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: length / 2) {
                        vDSP_ctozD($0, 2, &split, 1, vDSP_Length(length / 2))
                    }
                }
                vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                split.imagp[0] = 0 // drop the Nyquist term, which is packed into imagp[0]

                // taper the spectrum with a raised cosine, so the curve doesn't ring around sharp edges
                let bins = length / 2
                for bin in 1..<bins {
                    let taper = 0.5 * (1 + cos(Double.pi * Double(bin) / Double(bins)))
                    split.realp[bin] *= taper
                    split.imagp[bin] *= taper
                }

                vDSP_fft_zripD(setup, &split, 1, upLog2n, FFTDirection(kFFTDirection_Inverse))
            }
        }

        // back to interleaved real values, the transforms scale by 2 each way
        var upsampled = [Double](repeating: 0, count: upLength)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPDoubleSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                upsampled.withUnsafeMutableBufferPointer { upBuffer in
                    upBuffer.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: upLength / 2) {
                        vDSP_ztocD(&split, 1, $0, 2, vDSP_Length(upLength / 2))
                    }
                }
            }
        }
        var normal = 1 / Double(2 * length)
        vDSP_vsmulD(upsampled, 1, &normal, &upsampled, 1, vDSP_Length(upLength))

        // keep the first half, which covers the original values, at factor points for each value
        let points = (values.count - 1) * factor + 1
        let step = Double(upLength) / Double(count) / Double(factor) // upsampled samples for each point
        return (0..<points).map { point in
            let position = Double(point) * step
            let lower = min(Int(position), upLength - 1), upper = min(lower + 1, upLength - 1)
            let fraction = position - floor(position)
            return max(0, upsampled[lower] * (1 - fraction) + upsampled[upper] * fraction)
        }
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
