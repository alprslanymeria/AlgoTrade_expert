// Global değişkenler
bool isTradeOpened = false; // Günlük işlem kontrol bayrağı
int lastDealTicket = 0;     // Son işlem ticket'ı
string csvFileName = "Kapanan_Islemler.csv"; // Sabit CSV dosya adı

// CSV başlık bilgileri
string csvHeader = "Tarih,Saat,İşlem Tipi,Lot,Açılış Fiyatı,Kapanış Fiyatı,Stop Loss,Take Profit,Kar/Zarar,Pip\n";

int OnInit()
{
    Print("Expert Advisor başlatıldı.");
    
    // CSV dosyasının var olup olmadığını kontrol et, yoksa oluştur ve başlık ekle
    if(!FileIsExist(csvFileName, FILE_COMMON))
    {
        int fileHandle = FileOpen(csvFileName, FILE_WRITE|FILE_CSV|FILE_COMMON);
        if(fileHandle != INVALID_HANDLE)
        {
            FileWriteString(fileHandle, csvHeader);
            FileClose(fileHandle);
        }
    }
    
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    // Zaman bilgilerini al ve çözümle
    MqlDateTime tm = {};
    datetime currentTime = TimeCurrent();
    TimeToStruct(currentTime, tm);
    
    // Kapanan işlemleri kontrol et ve kaydet
    CheckClosedTrades();
    
    // 14:30'da işlem aç
    if(tm.hour == 14 && tm.min == 30 && !isTradeOpened)
    {
        bool result = OpenBuyOrder();
        if(result)
        {
            isTradeOpened = true;
            Print("BUY işlemi başarıyla açıldı.");
        }
        else
        {
            Print("BUY işlemi açılamadı!");
        }
    }
    
    // Gün değiştiğinde işlem açılabilir duruma getir
    if(tm.hour == 15 && tm.min == 30)
    {
        isTradeOpened = false;
    }
}

void CheckClosedTrades()
{
    HistorySelect(0, TimeCurrent()); // Tüm işlem geçmişini seç
    int totalDeals = HistoryDealsTotal();
    
    // En son kapanan işlemi kontrol et
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        
        // Eğer bu işlem daha önce kaydedilmemişse
        if(ticket > lastDealTicket)
        {
            // İşlem bilgilerini al
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) // Kapanış işlemi mi?
            {
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
                double closePrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
                datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
                ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
                
                // İlgili açılış işlemini bul
                ulong openPositionTicket = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
                double openPrice = 0.0, sl = 0.0, tp = 0.0;
                datetime openTime = 0;
                
                // Açılış işlem bilgilerini bul
                HistorySelectByPosition(openPositionTicket);
                int deals = HistoryDealsTotal();
                
                for(int j = 0; j < deals; j++)
                {
                    ulong dealTicket = HistoryDealGetTicket(j);
                    if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
                    {
                        openPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                        openTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                        break;
                    }
                }
                
                // Pip değerini hesapla
                double pips = MathAbs(closePrice - openPrice) / _Point;
                
                // CSV dosyasına kaydet
                SaveTradeToCSV(openTime, closeTime, dealType, volume, openPrice, 
                             closePrice, sl, tp, profit, pips);
                
                lastDealTicket = ticket; // Son işlemi güncelle
            }
        }
    }
}

void SaveTradeToCSV(datetime openTime, datetime closeTime, ENUM_DEAL_TYPE dealType,
                    double volume, double openPrice, double closePrice, 
                    double sl, double tp, double profit, double pips)
{
    // Dosyayı yazma modunda aç (Dosyayı her seferinde üzerine yazmadan aç)
    int fileHandle = FileOpen(csvFileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON);
    
    if(fileHandle == INVALID_HANDLE)
    {
        // Eğer dosya açılamıyorsa, yeni dosya oluştur ve başlık yaz
        fileHandle = FileOpen(csvFileName, FILE_WRITE | FILE_CSV | FILE_COMMON);
        if(fileHandle != INVALID_HANDLE)
        {
            FileWriteString(fileHandle, csvHeader); // Başlık yaz
        }
    }
    
    if(fileHandle != INVALID_HANDLE)
    {
        string dealTypeStr = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
        
        string csvLine = StringFormat("%s,%s,%s,%.2f,%.5f,%.5f,%.5f,%.5f,%.2f,%.1f\n",
                                    TimeToString(openTime, TIME_DATE),
                                    TimeToString(closeTime, TIME_MINUTES),
                                    dealTypeStr,
                                    volume,
                                    openPrice,
                                    closePrice,
                                    sl,
                                    tp,
                                    profit,
                                    pips);
                                    
        // Veriyi dosyaya ekle
        FileSeek(fileHandle, 0, SEEK_END);  // Dosyanın sonuna git
        FileWriteString(fileHandle, csvLine);  // Yeni satırı ekle
        FileClose(fileHandle);  // Dosyayı kapat
        
        Print("İşlem CSV dosyasına kaydedildi: ", csvFileName);
    }
    else
    {
        Print("CSV dosyası açılamadı! Hata kodu: ", GetLastError());
    }
}

bool OpenBuyOrder()
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = ask - 100 * _Point;
    double tp = ask + 100 * _Point;
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = 0.01;
    request.type = ORDER_TYPE_BUY;
    request.price = ask;
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = NormalizeDouble(tp, _Digits);
    request.deviation = 10;
    request.magic = 123456;
    
    if(OrderSend(request, result))
    {
        Print("BUY işlemi başarıyla açıldı: ", result.comment);
        return true;
    }
    else
    {
        Print("BUY işlemi açılamadı: ", result.comment);
        return false;
    }
}
