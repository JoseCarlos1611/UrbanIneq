import os
import tkinter as tk
from tkinter import filedialog, messagebox
from datetime import datetime

# Extensiones que normalmente conviene leer como texto/código
TEXT_EXTENSIONS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".java", ".c", ".cpp", ".h", ".hpp",
    ".cs", ".go", ".rs", ".php", ".rb", ".swift", ".kt", ".kts", ".scala",
    ".html", ".htm", ".css", ".scss", ".sass", ".less",
    ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".env",
    ".md", ".txt", ".sql", ".sh", ".bat", ".ps1",
    ".xml", ".vue", ".r", ".m", ".tex"
}

# Carpetas que normalmente no interesa incluir
SKIP_DIRS = {
    ".git", ".idea", ".vscode", "__pycache__", "node_modules",
    "dist", "build", ".next", ".venv", "venv", "env", ".mypy_cache"
}

# Archivos binarios o pesados que normalmente no interesa incluir
SKIP_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".ico",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
    ".zip", ".rar", ".7z", ".tar", ".gz",
    ".mp3", ".wav", ".mp4", ".avi", ".mov",
    ".exe", ".dll", ".so", ".bin", ".pyc", ".class"
}


def is_probably_text_file(filepath: str) -> bool:
    _, ext = os.path.splitext(filepath)
    ext = ext.lower()

    if ext in SKIP_EXTENSIONS:
        return False

    if ext in TEXT_EXTENSIONS:
        return True

    # Intento simple para archivos sin extensión o extensiones raras
    try:
        with open(filepath, "rb") as f:
            chunk = f.read(2048)
        if b"\x00" in chunk:
            return False
        return True
    except Exception:
        return False


def select_folders(root) -> list[str]:
    folders = []

    messagebox.showinfo(
        "Selección de carpetas",
        "Vas a poder seleccionar varias carpetas.\n\n"
        "Pulsa Cancelar cuando ya no quieras añadir más."
    )

    while True:
        folder = filedialog.askdirectory(title="Selecciona una carpeta")
        if not folder:
            break
        if folder not in folders:
            folders.append(folder)

        keep_adding = messagebox.askyesno(
            "Añadir otra carpeta",
            "¿Quieres añadir otra carpeta?"
        )
        if not keep_adding:
            break

    return folders


def collect_files(folders: list[str]) -> list[str]:
    collected = []

    for folder in folders:
        for current_root, dirnames, filenames in os.walk(folder):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]

            for filename in filenames:
                full_path = os.path.join(current_root, filename)
                if is_probably_text_file(full_path):
                    collected.append(full_path)

    collected.sort()
    return collected


def read_file_safely(filepath: str) -> str:
    encodings = ["utf-8", "utf-8-sig", "latin-1", "cp1252"]

    for enc in encodings:
        try:
            with open(filepath, "r", encoding=enc) as f:
                return f.read()
        except Exception:
            continue

    return "[NO SE PUDO LEER EL ARCHIVO CON CODIFICACIONES COMUNES]"


def build_output(files: list[str], base_folders: list[str]) -> str:
    lines = []
    lines.append("EXPORTACIÓN DE CÓDIGO")
    lines.append(f"Fecha: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("CARPETAS INCLUIDAS:")
    for folder in base_folders:
        lines.append(f"- {folder}")
    lines.append("")
    lines.append("=" * 100)
    lines.append("")

    for i, filepath in enumerate(files, start=1):
        content = read_file_safely(filepath)

        lines.append(f"[ARCHIVO {i}] {filepath}")
        lines.append("-" * 100)
        lines.append(content)
        lines.append("")
        lines.append("=" * 100)
        lines.append("")

    return "\n".join(lines)


def main():
    root = tk.Tk()
    root.withdraw()

    folders = select_folders(root)

    if not folders:
        messagebox.showwarning("Sin carpetas", "No has seleccionado ninguna carpeta.")
        return

    files = collect_files(folders)

    if not files:
        messagebox.showwarning(
            "Sin archivos",
            "No se encontraron archivos de texto/código en las carpetas seleccionadas."
        )
        return

    output_text = build_output(files, folders)

    output_path = filedialog.asksaveasfilename(
        title="Guardar archivo TXT generado",
        defaultextension=".txt",
        initialfile="codigo_exportado.txt",
        filetypes=[("Archivo de texto", "*.txt")]
    )

    if not output_path:
        messagebox.showinfo("Cancelado", "No se guardó ningún archivo.")
        return

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(output_text)

    messagebox.showinfo(
        "Completado",
        f"Archivo generado correctamente.\n\n"
        f"Se han incluido {len(files)} archivos.\n\n"
        f"Salida:\n{output_path}"
    )


if __name__ == "__main__":
    main()