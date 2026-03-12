// `foundation` ve `gestures` paketleri, Google Map widget'ı ile
// dokunma/gestures davranışlarını düzgün yönetmek için kullanılır.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// State yönetimi için Provider kullanılıyor. Buradan viewmodel'lere
// erişip veri ekleme/okuma işlemleri yapılacak.
import 'package:provider/provider.dart';

// Cihazın gerçek konumunu almak için Geolocator paketi.
import 'package:geolocator/geolocator.dart';

// Google Maps Flutter paketi, uygulama içi harita gösterimi ve
// kullanıcı etkileşimi için kullanılıyor.
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Firestore tarih/zaman ve GeoPoint tipi için kullanılıyor.
import 'package:cloud_firestore/cloud_firestore.dart';

// Proje içi view model ve model dosyalarını içe aktarıyoruz.
// Bunlar, bildirim oluşturma ve kullanıcı bilgisi almak için kullanılacak.
import '../../view_models/notification_view_model.dart';
import '../../view_models/auth_view_model.dart';
import '../../models/notification_model.dart';

// Bu sayfa yeni bir bildirim (veya acil duyuru) eklemek için kullanılan
// bir StatefulWidget'tır. Stateful olması, kullanıcı etkileşimleri
// (metin girişi, harita kaydırma, lokasyon seçimi vb.) sırasında
// durumun korunması gerektiğindendir.
class AddNewNotificationPage extends StatefulWidget {
  // Eğer bu sayfa 'acil duyuru' modunda açıldıysa, bu değişken true olur.
  // Örneğin admin kullanıcı acil duyuru butonuna bastığında bu sayfa
  // isEmergency = true ile açılır ve bazı alanlar kilitlenir/özel davranır.
  final bool isEmergency;

  // Constructor: isEmergency belirtilmezse varsayılan olarak false kabul edilir.
  const AddNewNotificationPage({
    super.key,
    this.isEmergency = false,
  });

  @override
  State<AddNewNotificationPage> createState() => _AddNewNotificationPageState();
}

class _AddNewNotificationPageState extends State<AddNewNotificationPage> {
  // Metin alanları için controller'lar: başlık ve açıklama girdilerini alır.
  // Controller'lar sayesinde girilen metinlere kolayca erişip işleyebiliriz.
  final titleController = TextEditingController();
  final descController = TextEditingController();

  // Bildirim türü: örn. "duyuru", "acil", "saglik" vb.
  // Varsayılan tür "duyuru" olarak başlatılır; eğer sayfa acil modda
  // açıldıysa initState içinde bu değer "acil" olarak değiştirilecektir.
  String selectedType = "duyuru";

  // Bildirimin başlangıç durumu veritabanına kaydolurken bu değer atanır.
  final String defaultStatus = "inceleniyor";

  // Seçilen konumu Firestore'un GeoPoint tipinde saklıyoruz.
  // Başlangıçta null olabilir (kullanıcı henüz konum seçmemişse).
  GeoPoint? selectedLocation;

  // Cihazdan konum alınırken yükleme göstergesi göstermek için bayrak.
  bool loadingLocation = false;

  // Konumun cihaz tarafından mı alındığını belirten bayrak. Eğer true ise
  // kullanıcı "Cihaz konumunu kullan" butonuna basmıştır.
  bool locationFromDevice = false;

  // Harita başlangıç konumu: kampüsün merkezi olarak belirlenmiş sabit koordinat.
  // Harita yüklendiğinde kamera bu konuma odaklanır. Kullanıcı haritayı
  // kaydırdıkça bu merkez güncellenecek ve onCameraIdle ile seçilen
  // koordinatlar `selectedLocation` olarak saklanacaktır.
  static const LatLng campusLocation = LatLng(39.9009, 41.2640);
  late LatLng mapCenter = campusLocation;

  @override
  void initState() {
    super.initState();
    // Eğer widget acil modda açıldıysa, form içindeki tür dropdown'ını
    // göstermemize gerek yok; tür otomatik olarak "acil" olmalı.
    if (widget.isEmergency) {
      selectedType = "acil";
    }
  }

  // 📱 Cihaz konumu al
  // Cihazın mevcut GPS konumunu alır ve haritayı bu konuma taşır.
  // 1) Kullanıcıdan konum izni istenir.
  // 2) İzin verilmezse işlem iptal edilir.
  // 3) İzin verildiğinde pozisyon alınır ve state güncellenir.
  Future<void> useDeviceLocation() async {
    // Kullanıcıya geri bildirim göstermek için loading bayrağını set ediyoruz.
    setState(() => loadingLocation = true);

    // Konum izni isteği: kullanıcının izin durumunu alıyoruz.
    final permission = await Geolocator.requestPermission();

    // Eğer izin reddedilmişse veya kalıcı olarak engellenmişse, yükleme
    // göstergesini kapatıp fonksiyonu sonlandırıyoruz.
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => loadingLocation = false);
      return;
    }

    // İzin verildiyse cihazın şu anki pozisyonunu alıyoruz.
    final pos = await Geolocator.getCurrentPosition();

    // Pozisyon alındıktan sonra harita merkezini ve seçili konumu güncelliyoruz,
    // ayrıca cihaz konumu alındı bayrağını true yapıyoruz ve yükleme kapatıyoruz.
    setState(() {
      mapCenter = LatLng(pos.latitude, pos.longitude);
      selectedLocation = GeoPoint(pos.latitude, pos.longitude);
      locationFromDevice = true;
      loadingLocation = false;
    });
  }

  // Eğer eksik veri varsa kullanıcıya SnackBar ile uyarı gösterir.
  Future<void> saveNotification() async {
    if (titleController.text.isEmpty ||
        descController.text.isEmpty ||
        selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tüm alanları doldurun")),
      );
      return;
    }

    try {
      // Geçerli kullanıcı bilgilerini AuthViewModel üzerinden alıyoruz.
      // `currentUser` null olmamalı; uygulama mantığına göre oturum açık.
      final user = context.read<AuthViewModel>().currentUser!;

      // NotificationModel nesnesini oluşturuyoruz; bu model veritabanına
      // gönderilecek verinin tamamını tutar. Tarih olarak Firestore'un
      // `Timestamp.now()` fonksiyonunu kullanıyoruz.
      final notif = NotificationModel(
        title: titleController.text.trim(),
        description: descController.text.trim(),
        type: selectedType, // örn. "acil" veya "duyuru" vb.
        status: defaultStatus, // başta "inceleniyor" olarak kaydedilir.
        location: selectedLocation!, // daha önce seçilmiş olmalı.
        date: Timestamp.now(),
        createdBy: user.uid,
        createdByName: user.name,
        followers: [], // başlangıçta takip eden yok.
      );

      // NotificationViewModel üzerinden veritabanına ekleme işlemini yapıyoruz.
      await context.read<NotificationViewModel>().addNotification(notif);

      // Eğer widget hâlâ ağaçta ise kullanıcıya başarılı mesajı gösterip
      // sayfayı kapatıyoruz. `mounted` kontrolü, async işlemler sırasında
      // widget'ın yok edilmiş olma durumuna karşı güvenlik sağlar.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text("Bildiriminiz başarıyla eklendi!"),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context); // Kayıttan sonra bir önceki ekrana dön.
      }
    } catch (e) {
      // Hata yakalandığında kullanıcıya hata mesajı göster.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Bir hata oluştu: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  //  Ortak Form Kartı
  // Form içindeki bölümleri görsel olarak birbirinden ayırmak için kullanılan
  // yardımcı widget. Tek bir yerden stil uygulamak için fonksiyon haline getirildi.
  Widget formCard({required Widget child}) {
    return Container(
      // Her kartın altında boşluk bırakıyoruz.
      margin: const EdgeInsets.only(bottom: 16),
      // İçerik ile kenar arasındaki boşluk.
      padding: const EdgeInsets.all(16),
      // Görsel stil: arka plan rengi, kenar yuvarlama ve sınır çizgisi.
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Kısa değişkene atama: widget'ın acil modda olup olmadığı.
    final isEmergency = widget.isEmergency;

    return Scaffold(
      // Sayfanın arka planı beyaz olarak ayarlanır.
      backgroundColor: Colors.white,
      // Üst AppBar: sayfanın başlığı ve geri butonu içerir.
      appBar: AppBar(
        title: Text(
          // Başlık, acil modda farklı olur.
          isEmergency ? "Yeni Acil Duyuru" : "Yeni Bildirim",
          style: const TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0, // Gölge yok, düz görünüm.
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      // Body içeriği kaydırılabilir olacak şekilde sarılıyor; böylece
      // klavye açıldığında veya küçük ekranlarda içerik taşmaz.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Eğer acil moddaysak kullanıcıya bunun açık olduğunu belirten
            // görsel bir uyarı gösteriyoruz. Bu alan zorunlu değildir ama
            // kullanıcı deneyimini iyileştirir.
            if (isEmergency)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  // Hafif kırmızı tonlu arka plan ile acil modu vurgulanır.
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    // Buradaki ikon ve metin sadece bilgi amaçlıdır.
                    Icon(Icons.warning_amber, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(
                      "ACİL DUYURU MODU AKTİF",
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Başlık giriş alanı: kullanıcıdan bildirim başlığını alır.
            formCard(
              child: TextField(
                controller: titleController,
                // Başlık çok uzun olabilir, multiline'e izin veriyoruz.
                keyboardType: TextInputType.multiline,
                enableSuggestions: true,
                autocorrect: true,
                decoration: const InputDecoration(
                  labelText: "Bildirim Başlığı",
                  border: InputBorder.none,
                ),
              ),
            ),

            // Açıklama alanı: daha uzun metinler için en az 4 satır gösterilir.
            formCard(
              child: TextField(
                controller: descController,
                minLines: 4,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                enableSuggestions: true,
                autocorrect: true,
                decoration: const InputDecoration(
                  labelText: "Açıklama",
                  border: InputBorder.none,
                ),
              ),
            ),

            // Bildirim türü seçimi: Eğer sayfa acil modda açıldıysa bu alan
            // gösterilmez çünkü tür zaten "acil" olarak atanmıştır.
            if (!isEmergency)
              formCard(
                child: DropdownButtonFormField(
                  // Dropdown'un seçili değeri state'ten okunur.
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: "Bildirim Türü",
                    border: InputBorder.none,
                  ),
                  // Tür seçenekleri sabit liste olarak verilmiştir.
                  items: const [
                    DropdownMenuItem(value: "duyuru", child: Text("Duyuru")),
                    DropdownMenuItem(value: "saglik", child: Text("Sağlık")),
                    DropdownMenuItem(value: "kayip", child: Text("Kayıp")),
                    DropdownMenuItem(value: "guvenlik", child: Text("Güvenlik")),
                    DropdownMenuItem(value: "cevre", child: Text("Çevre")),
                    DropdownMenuItem(value: "teknikAriza", child: Text("Teknik Arıza")),
                    DropdownMenuItem(value: "diger", child: Text("Diğer")),
                  ],
                  // Kullanıcı yeni bir tür seçtiğinde state güncellenir.
                  onChanged: (v) => setState(() => selectedType = v!),
                ),
              ),

            // Konum seçimi bölümü: cihaz konumunu kullanma butonu ve harita içerir.
            formCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cihazdan anlık konumu alır. Eğer halihazırda konum
                  // alınıyorsa buton disable edilir.
                  ElevatedButton.icon(
                    onPressed: loadingLocation ? null : useDeviceLocation,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      // Butonun metni, yükleme veya alınmış konuma göre değişir.
                      loadingLocation
                          ? "Konum alınıyor..."
                          : locationFromDevice
                          ? "Cihaz konumu alındı ✓"
                          : "Cihaz konumunu kullan",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      side: const BorderSide(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Harita: kullanıcı haritayı kaydırarak konum seçebilir.
                  SizedBox(
                    height: 250,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GoogleMap(
                        // Gesture recognizer ile harita ve üstündeki diğer
                        // kaydırma davranışlarının çakışmasını önlüyoruz.
                        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                        },
                        // Haritanın başlangıç kamera konumu.
                        initialCameraPosition: CameraPosition(
                          target: mapCenter,
                          zoom: 16,
                        ),
                        // Haritada cihaz konumu gösterilsin.
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        // Kamera hareket ettikçe mapCenter değişkenini güncelliyoruz.
                        onCameraMove: (pos) {
                          mapCenter = pos.target;
                        },
                        // Kamera hareketi durduğunda, o anki merkeze göre
                        // `selectedLocation` güncellenir. Bu şekilde kullanıcı
                        // haritayı kaydırıp konumu merkezde işaretleyebilir.
                        onCameraIdle: () {
                          setState(() {
                            selectedLocation = GeoPoint(
                              mapCenter.latitude,
                              mapCenter.longitude,
                            );
                          });
                        },
                        // Seçilen konumu gösteren işaretçi (marker).
                        markers: {
                          Marker(
                            markerId: const MarkerId("selected"),
                            position: mapCenter,
                          ),
                        },
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      "* Haritayı kaydırarak konumu belirleyebilirsiniz.",
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Kaydet butonu: form doğrulaması sonrası `saveNotification` çağrılır.
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: saveNotification,
                style: ElevatedButton.styleFrom(
                  // Eğer acil moddaysa buton kırmızı, aksi halde mavi.
                  backgroundColor: isEmergency ? Colors.red.shade700 : const Color(0xFF0D47A1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isEmergency ? "Acil Duyuru Yayınla" : "Bildirim Oluştur",
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
