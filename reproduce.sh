#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

cat > lib/src/main/kotlin/com/example/lib/Outer.kt << 'EOF'
package com.example.lib

class Outer {
    companion object {
        fun create(): Int = 1
    }
}
EOF

cat > app/src/main/kotlin/com/example/app/App.kt << 'EOF'
package com.example.app

import com.example.lib.Outer.Companion.create

fun useCompanion(): Int = create()
EOF

echo "=== Step 1: Clean build (:app:compileKotlin) ==="
./gradlew --no-daemon clean :app:compileKotlin "$@"

cat > lib/src/main/kotlin/com/example/lib/Outer.kt << 'EOF'
package com.example.lib

class Outer
EOF

cat > app/src/main/kotlin/com/example/app/App.kt << 'EOF'
package com.example.app

fun useCompanion(): Int = 1
EOF

echo "=== Step 2: Incremental build (:app:compileKotlin) ==="
./gradlew --no-daemon :app:compileKotlin --stacktrace "$@"
