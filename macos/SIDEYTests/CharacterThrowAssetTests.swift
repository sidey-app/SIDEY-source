import CryptoKit
import ImageIO
import XCTest
@testable import SIDEYAppStore

final class CharacterThrowAssetTests: XCTestCase {
    private let actionHashes = [
        "pixel_hamster": "b9915afdbb5476b17ea7b7f0a06eea09cc20b96dd1995328bdae2f806c3285c8",
        "pixel_cat": "128e020aab718d8d45e81f599c221467b46f27aa809c45b1d873580cdaffcc62",
        "pixel_puppy": "38d2858c97b456be17f34fd6b93df862e9c0d3b72e5592bb0e625e64110c5744",
        "pixel_rabbit": "f641ebbba64e8c23d33173ff04d4907d3e15955024dd72e3f6e7d9b3e20fec84",
        "pixel_penguin": "7ee5ea2b90994400a1b4dd252ed2affb095416597422a8ef4cb0ae54b3fb7f77",
        "pixel_guinea_pig": "384157773baa55bd4a5f8586d179ab7eb43f42fb4204c306490784551e38ae1d",
        "pixel_monkey": "059a288dde75695febec8a42303dc63f126636b094e3896b795b6a4ac1cce39a",
        "pixel_chinchilla": "a6dd2b4f1837812bc9fd0d979fe379c4362ed8018b9d5e6991e5c28d53265b02",
        "pixel_starlight_upalupa": "7a9bae8b1359f432857e026c972e3bc99777539ce7cfff89bc01e95d1938de75",
        "pixel_otter": "ad7d076f4c63910c2c97f6e6ed03c27b47642a825d002d64b8c9dc86c11c2716",
        "pixel_pig": "045344ec128ed34cfe2e6a641cf90c1a04b3ac639045dc200bc996c0089da85b",
        "pixel_tree": "af22b750129b813d0affd8fa572604837f6bf67acfa14bda68074abf45a11f15",
        "pixel_shiba": "0e2a54c5d53dd827526afca86ab3ec073f860da21ade1b1289b864c30f5a0e87",
        "pixel_duck": "ad802bb86d51eed5e2e5a1208da93503ff30c3886c5e21e8e40b86494a78881f",
        "pixel_poop": "2dfe350847ee18096f9e14431d573bf840f1445a4cef459622d77ca97760fc50",
        "pixel_tteokbokki": "f0f71c0d3843662a7ba80faf8c6476257adda33547e325ceea2031885ff5c5fc",
        "pixel_quokka": "ab43e2997d6e869ee6256a22a42f13ff76fc7b4f6a411f940319d7e98ab7a6f9"
    ]
    private let objectHashes = [
        "patch_soft_ball": "cdde7f417c5d8d82d0f4df6b03fa8e7d494d98a37d75aa66699505d7c87c53fe",
        "mini_paprika": "85b8d0525a865e531882a736561e9b7c4fbb6a2c3f80d91b456c4c4a7425724d",
        "banana": "9cfca454ff6305fdd374c08f64c3c21e3af278166ffe15f7f81a183bb214f138",
        "dust_bath_pouch": "b68022f5fe1a1a6a57fe56a01f73bae3d14b27d76f2dcbf10c6686b979634a65",
        "starlight_orb": "08cf8ec8dc680ae07dcd83de9d56948873445470c6b15b5ad22e770f4277984c",
        "throwable_bouncy_heart": "8474458c5d810a598c16a7f74bbfecf65300d7fb2c55aaaf0cabfa0399945305",
        "throwable_toy_cannon": "c42c472f216ec4d291a41562dfaf6a28204625133961a5a225198daf87459bef",
        "throwable_squeaky_duck": "3b6935398d41b6d1cd5efa922392dbf4864782deb9880c5d0f10885e00906e7a",
        "clam": "561832b15538e3f57b0b6381e967130f21ba1a0aaf74110019588ff90da874e0",
        "pork": "0a7acc60184321e05f7e0e04aed8972651331e50960aa18243b4958d27fd4da6",
        "timber": "21280bb2ac9f9df4332552281fcba6fc1efdaf27b933eb058bf625a30221b63b",
        "throwable_snowflake": "35ede7107f668d193c272773441215427da267e1f27b2beaab47d8c88ae37cd2",
        "throwable_baseball": "73f3dc8d86a9f8f76f07494df5ee48a8ff5380feec55a718eed8aad6940b94e5",
        "throwable_wakkuball": "4627c3538efcdaae3deda1ee390fbac92f96cf6e199dceb58a60f7917b7de295",
        "throwable_dujjonku": "bb2468a5a9f3a692c294c7546c2b20cd4bfdfc903e6779304b2bfeccaea50b32",
        "tennis_ball": "19c1a71275fd2e5be5be0b39ebd7be95d960f80ac65dd629aedd885b64f89fc3",
        "tissue_ball": "ae0a3d483f6a606b4dc35bdac173044720668679f6462e36ff19720334dea975",
        "fish_cake_skewer": "bdcfc04e33f3cf4f45305aa9fbf6c6fed70b515fe826823c890ccbb5e28340fd",
        "leaf": "b0a419e6659ded829130ec7d0be92d0b693ccd1cdc158aa8aabbd8b24936173e"
    ]
    private let bubbleDecorationHashes = [
        "bubble_bunny_pink": "3013d02224fe98befdc18f065f706c98cc412ab30c77a6a6c83723fc3366d117",
        "bubble_butter_chick": "4444b4bb579f0eaa322123e927078b3ad837ddba8fc5dea4cab5ab5bf2a39e56",
        "bubble_starry_cat": "da374fdafad2bfa1f9968ea0e438e1cad1391e72dbf84c2c408174b33ff04515"
    ]

    func testApprovedActionSheetsAreBundledAtExactSizeAndHash() throws {
        for (id, hash) in actionHashes {
            try assertAsset(
                url: PixelCharacterThrowCatalog.actionAssetURL(for: id),
                size: CGSize(width: 192, height: 24),
                hash: hash,
                label: id
            )
        }
    }

    func testApprovedObjectSheetsAreBundledAtExactSizeAndHash() throws {
        for (id, hash) in objectHashes {
            try assertAsset(
                url: PixelCharacterThrowCatalog.objectAssetURL(for: id),
                size: CGSize(width: 192, height: 16),
                hash: hash,
                label: id
            )
        }
    }

    func testApprovedCannonEmitterIsBundledSeparatelyFromItsProjectile() throws {
        try assertAsset(
            url: PixelCharacterThrowCatalog.emitterAssetURL(for: "throwable_toy_cannon"),
            size: CGSize(width: 96, height: 24),
            hash: "7869a47c2f72a17894646e2f63eab1166b42d13f2a72fa83311075b3d809ffbf",
            label: "throwable_toy_cannon_emitter"
        )
    }

    func testApprovedBubbleDecorationsAreBundledAtExactSizeAndHash() throws {
        for (id, hash) in bubbleDecorationHashes {
            let url = Bundle.main.url(forResource: id, withExtension: "png", subdirectory: "Bubbles")
                ?? Bundle.main.url(forResource: id, withExtension: "png")
            try assertAsset(
                url: url,
                size: CGSize(width: 16, height: 16),
                hash: hash,
                label: id
            )
        }
    }

    private func assertAsset(url: URL?, size: CGSize, hash: String, label: String) throws {
        let url = try XCTUnwrap(url, label)
        let data = try Data(contentsOf: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, Int(size.width), label)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, Int(size.height), label)
        XCTAssertEqual(SHA256.hash(data: data).hex, hash, label)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertNotEqual(image.alphaInfo, .none, label)
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
