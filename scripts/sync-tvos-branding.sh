#!/bin/bash
# Package the exact iOS artwork at the sizes required by the TV asset catalog.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
assets="$project_dir/Media Manager/Assets.xcassets"
brand="$assets/AppIcon.brandassets"
icon="$assets/AppIcon.appiconset/AppIcon.png"
splash="$assets/LaunchImage.imageset/LaunchImage@3x.png"

package_image() {
    local source="$1" width="$2" height="$3" background="$4" destination="$5"
    sips --resampleHeight "$height" "$source" --out "$destination" >/dev/null
    sips --padToHeightWidth "$height" "$width" --padColor "$background" "$destination" >/dev/null
}

package_image "$icon" 400 240 F4F4F4 "$brand/App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon-back.png"
package_image "$icon" 800 480 F4F4F4 "$brand/App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon-back@2x.png"
package_image "$icon" 1280 768 F4F4F4 "$brand/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/appstore-back.png"
package_image "$splash" 1920 720 05080F "$brand/Top Shelf Image.imageset/shelf.png"
package_image "$splash" 3840 1440 05080F "$brand/Top Shelf Image.imageset/shelf@2x.png"
package_image "$splash" 2320 720 05080F "$brand/Top Shelf Image Wide.imageset/shelf-wide.png"
package_image "$splash" 4640 1440 05080F "$brand/Top Shelf Image Wide.imageset/shelf-wide@2x.png"
