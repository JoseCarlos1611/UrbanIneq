import { Link, useLocation } from "react-router-dom";
import { BarChart3, Home, History } from "lucide-react";

export function AppLayout({ children }: { children: React.ReactNode }) {
  const { pathname } = useLocation();

  const links = [
    { to: "/", label: "Generador", icon: Home },
    { to: "/history", label: "Historial", icon: History },
  ];

  return (
    <div className="min-h-screen bg-background">
      <header className="border-b bg-card/80 backdrop-blur-sm sticky top-0 z-40">
        <div className="container flex items-center h-14 gap-6">
          <Link to="/" className="flex items-center gap-2 font-bold text-lg">
            <BarChart3 className="w-5 h-5 text-primary" />
            <span className="gradient-text">Unfair Urban Data</span>
          </Link>
          <nav className="flex items-center gap-1 ml-auto">
            {links.map((l) => (
              <Link
                key={l.to}
                to={l.to}
                className={`flex items-center gap-2 px-3 py-2 rounded-md text-sm transition-colors ${
                  pathname === l.to
                    ? "bg-primary/10 text-primary font-medium"
                    : "text-muted-foreground hover:text-foreground hover:bg-muted"
                }`}
              >
                <l.icon className="w-4 h-4" />
                {l.label}
              </Link>
            ))}
          </nav>
        </div>
      </header>
      <main className="container py-8">{children}</main>
    </div>
  );
}
