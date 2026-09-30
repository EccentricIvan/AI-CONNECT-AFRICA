# Keep llama.cpp / ggml JNI symbols.
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
-dontwarn org.bouncycastle.jsse.BCSSLParameters
-dontwarn org.bouncycastle.jsse.BCSSLSocket
-dontwarn org.bouncycastle.jsse.provider.BouncyCastleJsseProvider
-dontwarn org.conscrypt.Conscrypt$Version
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.ConscryptHostnameVerifier
-dontwarn org.openjsse.javax.net.ssl.SSLParameters
-dontwarn org.openjsse.javax.net.ssl.SSLSocket
-dontwarn org.openjsse.net.ssl.OpenJSSE

# Keep MediaPipe framework classes used via JNI/reflection by LiteRT-LM.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }

# fllama / llama.cpp dependencies reference annotation-processing and
# auto-value classes that are not present at runtime. Suppress R8 warnings.
-dontwarn javax.lang.model.**
-dontwarn javax.tools.**
-dontwarn javax.annotation.**
-dontwarn autovalue.shaded.**
-dontwarn com.google.auto.**
-dontwarn com.squareup.javapoet.**

# ML Kit text recognition (scanned PDF pages): only the bundled Latin model
# is included. The plugin still references the optional script recognisers,
# which R8 would otherwise report as missing classes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
