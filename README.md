# Voice to Color

<div align="left">
  <a href="https://saweria.co/nunugraha17">
    <img src="https://img.shields.io/badge/Traktir%20di-Saweria-orange?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Saweria" />
  </a>
  <a href="https://www.buymeacoffee.com/nunutech401">
    <img src="https://img.shields.io/badge/Buy%20Me%20A-Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me A Coffee" />
  </a>
</div>

---

Voice to Color adalah aplikasi iPhone yang mengubah karakter suara menjadi visual dan interpretasi mood secara real-time.

Aplikasi ini tidak mencoba membaca pikiran atau menentukan emosi pengguna secara mutlak. Aplikasi menganalisis karakter akustik suara—seperti energi, perubahan frekuensi, ketajaman, jeda, dan noise—lalu menerjemahkannya menjadi warna, grafik, dan kesimpulan mood.

## Konsep utama

```text
Suara dari microphone
  → analisis audio lokal
  → fitur akustik
  → valence + arousal
  → emotion family
  → warna dan grafik
  → kesimpulan sesi
```

Contoh interpretasi visual:

- Hijau/teal: suara cenderung tenang dan stabil.
- Merah: energi tinggi dan perubahan tajam, dapat terasa tegang atau kesal.
- Biru: energi rendah dan cenderung murung.
- Ungu: energi tinggi tetapi tidak stabil.
- Kuning/oranye: energi positif atau meningkat.

Warna merupakan interpretasi visual yang dapat dikalibrasi, bukan aturan universal bahwa satu emosi selalu memiliki satu warna.

## Cara kerja aplikasi

### Saat Listening

Aplikasi menampilkan `Live Audio Chart` yang bergerak mengikuti suara saat ini. Grafik memperlihatkan:

- level energi/volume sebagai area dan garis utama;
- spectral sharpness sebagai garis pembanding;
- warna chart yang mengikuti mood suara saat ini.

### Saat Stop

Aplikasi membuat `Emotion Timeline` dari seluruh sesi. Setiap bagian timeline memiliki warna berdasarkan mood yang terdeteksi pada bagian tersebut.

Contohnya, sesi dapat terlihat seperti:

```text
tenang ─ tenang ─ tegang ─ tenang ─ antisipasi
 hijau     hijau     merah     hijau       oranye
```

Aplikasi juga menampilkan ringkasan yang lebih mudah dipahami, misalnya:

> Karakter suaramu terdengar tenang dan cukup stabil, dengan kecenderungan positif ringan. Ada perubahan singkat menuju antisipasi.

## Fitur

- Analisis suara real-time.
- Live audio chart menggunakan Swift Charts.
- Emotion timeline setelah sesi selesai.
- Session summary berupa energi rata-rata, peak, valence, arousal, mood dominan, dan mood sekunder.
- Replay sesi secara lokal.
- Speech Recognition untuk membuat transcript sementara.
- Analisis AI dan roasting otomatis setelah sesi selesai.
- Penyimpanan audio sementara di RAM dengan batas buffer.
- Adaptive noise floor untuk membantu membaca suara lemah dan kebisingan ruangan.
- Signal-to-noise estimation.
- Tidak membuat file rekaman.
- Tidak mengunggah audio ke server.

## Teknologi

- SwiftUI — UI dan layout.
- Swift Charts — live chart dan emotion timeline.
- AVAudioSession — permission dan konfigurasi audio.
- AVAudioEngine — microphone capture dan audio tap.
- AVAudioPCMBuffer — buffer PCM sementara.
- Accelerate/vDSP — windowing, FFT, magnitude, spectral sharpness, dan spectral flux.
- AVAudioPlayerNode — replay audio dari buffer RAM.
- Swift concurrency dan MainActor — pengiriman state ke UI.
- Speech — transcript suara sementara.
- URLSession — request ke endpoint OpenAI-compatible 9Router.

## Algoritma utama

### 1. RMS energy

Mengukur kekuatan suara dari setiap buffer PCM.

```text
rms = sqrt(sum(sample²) / jumlah sample)
```

Nilai ini memengaruhi energy, tinggi grafik, brightness, dan arousal.

### 2. Adaptive noise floor

Aplikasi memperkirakan baseline noise ketika suara sedang rendah. Baseline tersebut dipakai untuk membedakan sinyal pengguna dari suara ambient ruangan.

```text
signalToNoise = (energy - noiseFloor) / noiseFloor
```

Ini membantu pada lingkungan seperti kantor atau coffee shop, tetapi tidak dapat memulihkan suara yang sepenuhnya tertutup noise.

### 3. FFT dan spectral sharpness

FFT mengubah sampel audio dari domain waktu menjadi spektrum frekuensi. Spectral sharpness membantu membaca apakah karakter suara lebih rendah/dull atau lebih tajam/tinggi.

### 4. Spectral flux

Spectral flux membandingkan spektrum frame sekarang dengan frame sebelumnya. Nilai tinggi menunjukkan perubahan suara yang mendadak dan dapat memengaruhi tension, pulse, atau warna.

### 5. Valence dan arousal

Fitur audio yang telah dinormalisasi dan di-smoothing dipetakan ke dua dimensi:

- `valence`: cenderung negatif ↔ positif;
- `arousal`: energi rendah ↔ energi tinggi.

Kemudian `AffectMapper` memilih emotion family seperti `Trust`, `Sadness`, `Anger`, `Fear`, `Joy`, `Surprise`, `Disgust`, atau `Anticipation`.

`AffectMapper` adalah ruleset produk yang dibuat dan diuji di dalam aplikasi. Ini bukan API bawaan iOS dan bukan model machine learning universal.

## AI analysis dan roasting

Setelah sesi dihentikan, aplikasi otomatis mengirim data ringkas berikut ke 9Router dan memasukkan hasil pembacaan ke kartu `SESSION SUMMARY`. Tidak ada panel API key di UI; konfigurasi 9Router berasal dari file lokal development:

- transcript sementara;
- mood dominan dan mood sekunder;
- energi rata-rata dan peak;
- valence dan arousal;
- durasi sesi.

Konfigurasi default:

```text
Base URL: https://9router.103-59-94-121.nip.io/v1
Model: codexCombo
Endpoint: /chat/completions
```

API key disimpan di file konfigurasi lokal yang di-ignore Git untuk development. Untuk production, pindahkan request ini ke backend agar key tidak dapat diekstrak dari aplikasi iPhone.

Roasting dibuat playful dan tidak boleh menjadi diagnosis psikologis atau mengarang isi ucapan.

## Privasi

Audio diproses secara lokal di perangkat.

- Audio mentah hanya berada sementara di RAM selama sesi.
- Replay hanya dilakukan ketika pengguna menekan Replay.
- Tombol Discard menghapus buffer sesi.
- Tidak ada file audio yang dibuat.
- Tidak ada upload atau transmisi audio mentah.
- Transcript sementara dan ringkasan fitur dikirim ke AI otomatis setelah sesi dihentikan.
- Hasil AI diminta membahas kondisi secara umum dan melakukan roasting ringan tanpa mengutip atau membocorkan ucapan sensitif.
- Permission microphone diminta setelah pengguna menekan Start.

## Struktur kode

```text
ConvertAudioToColor/
├── ContentView.swift
├── Models.swift
├── AudioMath.swift
├── AudioAnalyzer.swift
├── AIAnalysisService.swift
├── AudioServices.swift
├── AffectMapper.swift
├── VoiceVisualizerViewModel.swift
└── ConvertAudioToColorApp.swift
```

## Dokumentasi desain

- [Product and technical design](voice-to-color-design.md)
- [Flowcharts and technology map](audio-to-emotion-flowcharts.md)

## Status implementasi

Implementasi saat ini sudah mencakup live audio capture, audio analysis, affect mapping, live chart, emotion timeline setelah sesi selesai, session summary, replay lokal, adaptive noise detection, Speech Recognition, dan integrasi 9Router untuk analisis transcript serta roasting otomatis setelah sesi dihentikan.

Build aplikasi berhasil dilakukan dengan Xcode. Validasi microphone, speaker, dan kualitas deteksi tetap perlu dilakukan di iPhone fisik karena Simulator tidak mewakili input microphone nyata.

## Catatan interpretasi

Hasil aplikasi harus dibaca sebagai:

> “Karakter suara ini terdengar seperti...”

bukan:

> “Pengguna pasti sedang merasakan emosi ini.”

Suara keras belum tentu marah, suara pelan belum tentu sedih, dan warna emosi dapat dipengaruhi konteks, budaya, perangkat, jarak microphone, serta noise ruangan.
