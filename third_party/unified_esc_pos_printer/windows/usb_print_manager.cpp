#include "usb_print_manager.h"

#include <setupapi.h>
#include <tchar.h>
#include <wctype.h>

#include <codecvt>
#include <locale>

namespace unified_esc_pos_printer {

// ── Helpers ──────────────────────────────────────────────────────────────

static std::string WideToUtf8(const wchar_t* wide) {
  if (!wide || !*wide) return {};
  int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 0) return {};
  std::string out(len - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), len, nullptr, nullptr);
  return out;
}

static std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (len <= 0) return {};
  std::wstring out(len, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), len);
  return out;
}

// ── UsbPrintManager ──────────────────────────────────────────────────────

UsbPrintManager::UsbPrintManager() {}

UsbPrintManager::~UsbPrintManager() {
  Close();
}

std::vector<PrinterInfo> UsbPrintManager::ListPrinters() {
  std::vector<PrinterInfo> printers;

  // Query the default printer name.
  DWORD default_size = 0;
  GetDefaultPrinterW(nullptr, &default_size);
  std::wstring default_name(default_size, L'\0');
  bool has_default = false;
  if (default_size > 0 && GetDefaultPrinterW(default_name.data(), &default_size)) {
    default_name.resize(default_size - 1);  // strip trailing NUL
    has_default = true;
  }

  // Enumerate installed printers (local + network connections).
  DWORD needed = 0, returned = 0;
  DWORD flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
  EnumPrintersW(flags, nullptr, 2, nullptr, 0, &needed, &returned);
  if (needed == 0) return printers;

  std::vector<BYTE> buffer(needed);
  if (!EnumPrintersW(flags, nullptr, 2, buffer.data(), needed, &needed, &returned)) {
    return printers;
  }

  auto* info = reinterpret_cast<PRINTER_INFO_2W*>(buffer.data());
  for (DWORD i = 0; i < returned; ++i) {
    bool is_default = has_default &&
        _wcsicmp(info[i].pPrinterName, default_name.c_str()) == 0;

    bool is_available =
        (info[i].Status &
         (PRINTER_STATUS_NOT_AVAILABLE | PRINTER_STATUS_ERROR |
          PRINTER_STATUS_OFFLINE | PRINTER_STATUS_PAUSED)) == 0;

    printers.push_back(PrinterInfo{
        WideToUtf8(info[i].pPrinterName),
        WideToUtf8(info[i].pDriverName),
        is_default,
        is_available,
    });
  }

  return printers;
}

// GUID_DEVINTERFACE_USBPRINT: the interface usbprint.sys registers for each
// plugged-in USB printer. usbmon names its ports from the interface's
// "Base Name" + "Port Number" values (USB + 1 -> USB001).
static const GUID kUsbPrintInterface = {
    0x28d78fad, 0x5a12, 0x11d1, {0xae, 0x5b, 0x00, 0x00, 0xf8, 0x03, 0xa8, 0xc2}};

// usbmon ports (USB001, USB002…) of USB printers that are present right now.
static std::vector<std::wstring> PresentUsbPorts() {
  std::vector<std::wstring> ports;
  HDEVINFO devs = SetupDiGetClassDevsW(&kUsbPrintInterface, nullptr, nullptr,
                                       DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (devs == INVALID_HANDLE_VALUE) return ports;
  SP_DEVICE_INTERFACE_DATA iface = {};
  iface.cbSize = sizeof(iface);
  for (DWORD i = 0; SetupDiEnumDeviceInterfaces(devs, nullptr, &kUsbPrintInterface, i, &iface); ++i) {
    HKEY key = SetupDiOpenDeviceInterfaceRegKey(devs, &iface, 0, KEY_READ);
    if (key == INVALID_HANDLE_VALUE) continue;
    wchar_t base[64] = {};
    DWORD base_size = sizeof(base) - sizeof(wchar_t);
    DWORD number = 0, number_size = sizeof(number);
    if (RegQueryValueExW(key, L"Base Name", nullptr, nullptr, reinterpret_cast<LPBYTE>(base), &base_size) == ERROR_SUCCESS &&
        RegQueryValueExW(key, L"Port Number", nullptr, nullptr, reinterpret_cast<LPBYTE>(&number), &number_size) == ERROR_SUCCESS) {
      wchar_t port[96];
      swprintf_s(port, L"%s%03lu", base, number);
      ports.emplace_back(port);
    }
    RegCloseKey(key);
  }
  SetupDiDestroyDeviceInfoList(devs);
  return ports;
}

// True for a usbmon port name: "USB" followed only by digits.
static bool IsUsbmonPort(const std::wstring& port) {
  if (port.size() < 4 || _wcsnicmp(port.c_str(), L"USB", 3) != 0) return false;
  for (size_t i = 3; i < port.size(); ++i) {
    if (!iswdigit(port[i])) return false;
  }
  return true;
}

std::string UsbPrintManager::CheckReady(const std::string& printer_name) {
  std::wstring wide_name = Utf8ToWide(printer_name);
  HANDLE h = INVALID_HANDLE_VALUE;
  if (!OpenPrinterW(const_cast<LPWSTR>(wide_name.c_str()), &h, nullptr)) {
    return "Printer \"" + printer_name + "\" is not installed in Windows";
  }

  std::string reason;
  DWORD needed = 0;
  GetPrinterW(h, 2, nullptr, 0, &needed);
  std::vector<BYTE> buffer(needed);
  if (needed == 0 || !GetPrinterW(h, 2, buffer.data(), needed, &needed)) {
    ClosePrinter(h);
    return "Can't read the printer status from Windows";
  }
  auto* info = reinterpret_cast<PRINTER_INFO_2W*>(buffer.data());
  const DWORD st = info->Status;

  if (info->Attributes & PRINTER_ATTRIBUTE_WORK_OFFLINE) {
    reason = "Set to \"Use printer offline\" in Windows";
  } else if (st & PRINTER_STATUS_PAUSED) {
    reason = "Printing is paused in Windows";
  } else if (st & (PRINTER_STATUS_PAPER_OUT | PRINTER_STATUS_PAPER_PROBLEM)) {
    reason = "Out of paper";
  } else if (st & PRINTER_STATUS_DOOR_OPEN) {
    reason = "Printer cover is open";
  } else if (st & (PRINTER_STATUS_OFFLINE | PRINTER_STATUS_NOT_AVAILABLE)) {
    reason = "Printer is offline. Check it is switched on and the cable is in";
  } else if (st & (PRINTER_STATUS_ERROR | PRINTER_STATUS_USER_INTERVENTION | PRINTER_STATUS_PAPER_JAM)) {
    reason = "Printer has an error. Check paper and cover";
  }

  // A USB printer that is unplugged or switched off usually still shows "Ready"
  // in the spooler; the only sign is that its USB device has gone away.
  if (reason.empty() && info->pPortName) {
    std::vector<std::wstring> usb_ports;
    std::wstring all(info->pPortName);
    size_t start = 0;
    while (start <= all.size()) {
      size_t comma = all.find(L',', start);
      std::wstring p = all.substr(start, comma == std::wstring::npos ? std::wstring::npos : comma - start);
      while (!p.empty() && iswspace(p.front())) p.erase(p.begin());
      while (!p.empty() && iswspace(p.back())) p.pop_back();
      if (IsUsbmonPort(p)) usb_ports.push_back(p);
      if (comma == std::wstring::npos) break;
      start = comma + 1;
    }
    if (!usb_ports.empty()) {
      bool present = false;
      for (const auto& live : PresentUsbPorts()) {
        for (const auto& p : usb_ports) {
          if (_wcsicmp(live.c_str(), p.c_str()) == 0) present = true;
        }
      }
      if (!present) reason = "Printer is not connected. Check it is switched on and the USB cable is in";
    }
  }

  // Jobs the spooler couldn't deliver mean nothing is coming out of this printer.
  if (reason.empty() && info->cJobs > 0) {
    DWORD jobs_needed = 0, jobs_returned = 0;
    EnumJobsW(h, 0, 32, 1, nullptr, 0, &jobs_needed, &jobs_returned);
    if (jobs_needed > 0) {
      std::vector<BYTE> jobs(jobs_needed);
      if (EnumJobsW(h, 0, 32, 1, jobs.data(), jobs_needed, &jobs_needed, &jobs_returned)) {
        auto* job = reinterpret_cast<JOB_INFO_1W*>(jobs.data());
        for (DWORD i = 0; i < jobs_returned; ++i) {
          if (job[i].Status & (JOB_STATUS_ERROR | JOB_STATUS_OFFLINE | JOB_STATUS_PAPEROUT |
                               JOB_STATUS_BLOCKED_DEVQ | JOB_STATUS_USER_INTERVENTION)) {
            reason = "Print jobs are stuck in the Windows queue. Check the printer, then clear its queue";
            break;
          }
        }
      }
    }
  }

  ClosePrinter(h);
  return reason;
}

bool UsbPrintManager::Open(const std::string& printer_name) {
  Close();  // close any previous handle

  std::wstring wide_name = Utf8ToWide(printer_name);
  if (!OpenPrinterW(const_cast<LPWSTR>(wide_name.c_str()), &printer_handle_, nullptr)) {
    printer_handle_ = INVALID_HANDLE_VALUE;
    return false;
  }
  return true;
}

bool UsbPrintManager::PrintBytes(const std::vector<uint8_t>& data) {
  if (printer_handle_ == INVALID_HANDLE_VALUE || data.empty()) return false;

  DOC_INFO_1W doc_info = {};
  doc_info.pDocName = const_cast<LPWSTR>(L"ESC/POS Print Job");
  doc_info.pOutputFile = nullptr;
  doc_info.pDatatype = const_cast<LPWSTR>(L"RAW");

  DWORD job_id = StartDocPrinterW(printer_handle_, 1, reinterpret_cast<LPBYTE>(&doc_info));
  if (job_id == 0) return false;

  bool ok = false;
  if (StartPagePrinter(printer_handle_)) {
    DWORD written = 0;
    ok = WritePrinter(printer_handle_,
                      const_cast<LPVOID>(static_cast<const void*>(data.data())),
                      static_cast<DWORD>(data.size()),
                      &written) &&
         written == static_cast<DWORD>(data.size());
    EndPagePrinter(printer_handle_);
  }

  EndDocPrinter(printer_handle_);
  return ok;
}

bool UsbPrintManager::Close() {
  if (printer_handle_ != INVALID_HANDLE_VALUE) {
    ClosePrinter(printer_handle_);
    printer_handle_ = INVALID_HANDLE_VALUE;
    return true;
  }
  return false;
}

}  // namespace unified_esc_pos_printer
