import CryptoKit
import ImageIO
import XCTest
@testable import SIDEYAppStore

final class PixelHamsterAssetTests: XCTestCase {
    private let expectedHashes = [
        "pixel_hamster": "43171c1dd614629058b6d593c57ca0e5841b0be03a04a05181dfda67c53a7f45",
        "pixel_cat": "d8b370c03b5cf0ede6aa0d9fa6210030e164b015a920622e89ae86f835e018b2",
        "pixel_puppy": "8f56a5fda51a224802f41d6d1c359a138c83036b7da3e0a35777f9f4ed38d5f7",
        "pixel_rabbit": "f8e53749200a284f7729ea9baac3237a9fac0caf8efedf9102dcee065e521342",
        "pixel_penguin": "f171503f8ffb938732583a4b6f42443e7a69120bb17496f6e8d34372da2ea886",
        "pixel_guinea_pig": "1a0bf85dae86f2e6bb460e8b0b852c2bd010d5ff6f7efd1477cbd6986da64f5b",
        "pixel_monkey": "515fe377f5344dd4cbaa2b0faf58de3ce72fdc62be5aff6a9d9de683983c783b",
        "pixel_chinchilla": "c0009e007a7a63029fb58ad6f94d2b9a8c9ae7a55f139dd4892050f11614c5d4",
        "pixel_starlight_upalupa": "d180810a8796280077f3f70f6da681888c583c2f8d74776d0f5d300e943a079a",
        "pixel_otter": "38ebed0f4588e4f776df44872c2e81e96d70056fb8c97b19c812433584e4b5db",
        "pixel_pig": "b383c07699cc40fe21c05f18aaf21730888685f9b0874a16b95cd82bebcd6f98",
        "pixel_tree": "ddf40aa115034c2c4fb3046673f6e20d2ca208d0b5a9ffa5737fb79c2e6cc97f",
        "pixel_shiba": "f0fbdc42e774c4fc005b6712d7361f1032864c71f1dae6a62d4f631483de647f",
        "pixel_duck": "007e181fc7546b5346fc52746daf60985fe6113f366795a8c90f21d1b084e559",
        "pixel_poop": "0f2853654e953abe92fbfbd8894df1396f28fc32fe06db9b5c3db60197da1c43",
        "pixel_tteokbokki": "1da9b6df95412bfc52df6dc21157d2708a40f508de48cb3f9c8764ca7a378b92",
        "pixel_quokka": "55965cec0be9ac26787c255c92dd6ca5300164a505e12e506be2f87c010dcf3a"
    ]

    func testAllRuntimeSheetsAreTen24PixelFramesWithAlphaAndStableHashes() throws {
        XCTAssertEqual(PixelCharacterCatalog.all.count, 17)
        for character in PixelCharacterCatalog.all {
            let url = try XCTUnwrap(character.assetURL(), character.id)
            let data = try Data(contentsOf: url)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            )
            XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 240, character.id)
            XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 24, character.id)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertNotEqual(image.alphaInfo, .none, character.id)
            XCTAssertEqual(SHA256.hash(data: data).hex, expectedHashes[character.id], character.id)
        }
        XCTAssertEqual(PixelCharacterAsset.frameCount, 10)
        XCTAssertEqual(PixelCharacterAsset.framePixelSize, CGSize(width: 24, height: 24))
    }

    func testEveryFrameSharesTheSameLowestOpaquePixelBaseline() throws {
        for character in PixelCharacterCatalog.all {
            let url = try XCTUnwrap(character.assetURL())
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let width = image.width
            let height = image.height
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }

            let baselines = (0..<PixelCharacterCatalog.frameCount).map { frame -> Int in
                var lowestMemoryRow = Int.min
                for y in 0..<height {
                    for x in (frame * 24)..<((frame + 1) * 24) {
                        if rgba[(y * width + x) * 4 + 3] > 0 {
                            lowestMemoryRow = max(lowestMemoryRow, y)
                        }
                    }
                }
                return height - 1 - lowestMemoryRow
            }
            XCTAssertEqual(Set(baselines).count, 1, "\(character.id): \(baselines)")
            XCTAssertEqual(baselines.first, PixelCharacterCatalog.footBaselinePixel, character.id)
        }
    }

    func testGuineaPigWalkFramesBobWithTwoFeetAndSafeEarMargin() throws {
        let character = PixelCharacterCatalog.definition(for: PixelCharacterCatalog.pixelGuineaPigID)
        let url = try XCTUnwrap(character.assetURL())
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var topOpaqueRows: [Int] = []
        var baselineRunCounts: [Int] = []
        for frame in character.frames.walk {
            for y in 0..<2 {
                for x in (frame * 24)..<((frame + 1) * 24) {
                    XCTAssertEqual(rgba[(y * width + x) * 4 + 3], 0, "walk frame \(frame), x=\(x), y=\(y)")
                }
            }

            let frameX = frame * 24
            let topRow = try XCTUnwrap((0..<height).first { y in
                (0..<24).contains { x in rgba[(y * width + frameX + x) * 4 + 3] > 0 }
            })
            topOpaqueRows.append(topRow)

            let baselineMemoryRow = height - 1 - PixelCharacterCatalog.footBaselinePixel
            var runCount = 0
            var wasOpaque = false
            for x in 0..<24 {
                let isOpaque = rgba[(baselineMemoryRow * width + frameX + x) * 4 + 3] > 0
                if isOpaque && !wasOpaque { runCount += 1 }
                wasOpaque = isOpaque
            }
            baselineRunCounts.append(runCount)
        }
        XCTAssertEqual(topOpaqueRows, [5, 4, 5, 4])
        XCTAssertEqual(baselineRunCounts, [2, 1, 2, 1])
    }

    func testCatalogAndFallbackContracts() {
        XCTAssertEqual(PixelCharacterCatalog.all.map(\.id), [
            "pixel_hamster", "pixel_cat", "pixel_puppy", "pixel_rabbit", "pixel_penguin",
            "pixel_guinea_pig", "pixel_monkey", "pixel_chinchilla",
            "pixel_starlight_upalupa", "pixel_otter", "pixel_pig", "pixel_tree",
            "pixel_shiba", "pixel_duck", "pixel_poop", "pixel_tteokbokki", "pixel_quokka"
        ])
        XCTAssertEqual(PixelCharacterCatalog.free.count, 5)
        for character in PixelCharacterCatalog.all where character.entitlementKey != nil {
            XCTAssertFalse(PixelCharacterCatalog.canSelect(character.id, entitlementKeys: []))
            XCTAssertTrue(PixelCharacterCatalog.canSelect(
                character.id,
                entitlementKeys: [try! XCTUnwrap(character.entitlementKey)]
            ))
        }
        XCTAssertEqual(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelStarlightUpalupaID
        ).sparkleEffect, .starlight)
        XCTAssertTrue(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelStarlightUpalupaID
        ).mirrorsToMovementDirection)
        XCTAssertTrue(PixelCharacterCatalog.definition(
            for: PixelCharacterCatalog.pixelGuineaPigID
        ).mirrorsToMovementDirection)
        XCTAssertEqual(
            PixelCharacterCatalog.canonicalID(for: PixelCharacterCatalog.legacyPixelKoalaID),
            PixelCharacterCatalog.pixelChinchillaID
        )
        XCTAssertEqual(
            PixelCharacterCatalog.definition(for: PixelCharacterCatalog.legacyPixelKoalaID).displayName,
            "아기 친칠라"
        )
        XCTAssertTrue(PixelCharacterCatalog.free.allSatisfy { !$0.mirrorsToMovementDirection })
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientDelay, 1.0...1.4)
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientDuration, 1.05)
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientCount, 4...6)
        XCTAssertEqual(PixelSparkleEffect.starlight.ambientRadius, 2.6...4.0)
        XCTAssertEqual(PixelSparkleEffect.starlight.centralFlashDuration, 0.32)
        XCTAssertEqual(PixelSparkleEffect.starlight.centralFlashRadius, 34)
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseWaves.map(\.count), [18, 24])
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseWaves.map(\.distance), [126...168, 82...132])
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseWaves.map(\.radius), [8...13, 4.5...8])
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseCount, 42)
        XCTAssertEqual(PixelSparkleEffect.starlight.pulseDuration, 0.84, accuracy: 0.001)
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "minty_pup"), "pixel_hamster")
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "pixel_cat"), "pixel_cat")
        XCTAssertEqual(PixelCharacterCatalog.canonicalID(for: "unknown"), "pixel_hamster")
        XCTAssertEqual(PixelCharacterCatalog.definition(for: "unknown").displayName, "아기 햄스터")
        for character in PixelCharacterCatalog.all {
            XCTAssertEqual(character.frames, .standard)
        }
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
