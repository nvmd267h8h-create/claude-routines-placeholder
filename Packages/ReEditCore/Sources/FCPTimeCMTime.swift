#if canImport(CoreMedia)
    import CoreMedia

    // CoreMedia interop exists only on Apple platforms. Edit logic never needs it;
    // it exists for AVFoundation boundaries (proxy playback, thumbnails) in later
    // phases.
    extension FCPTime {
        /// Creates an exact rational time from a numeric `CMTime`.
        /// - Throws: `FCPTimeError.cmTimeNotNumeric` for invalid, indefinite or
        ///   infinite times, or non-positive timescales.
        public init(_ time: CMTime) throws(FCPTimeError) {
            guard time.isNumeric, time.timescale > 0 else {
                throw FCPTimeError.cmTimeNotNumeric(
                    details: "value \(time.value), timescale \(time.timescale), flags \(time.flags.rawValue)")
            }
            try self.init(numerator: time.value, denominator: Int64(time.timescale))
        }

        /// Converts to `CMTime` exactly, or throws — never rescales lossily.
        /// - Throws: `FCPTimeError.cmTimescaleUnrepresentable` when the reduced
        ///   denominator exceeds `CMTimeScale` (`Int32`) range.
        public func toCMTime() throws(FCPTimeError) -> CMTime {
            guard denominator <= Int64(Int32.max) else {
                throw FCPTimeError.cmTimescaleUnrepresentable(denominator: denominator)
            }
            return CMTime(value: numerator, timescale: Int32(denominator))
        }
    }
#endif
