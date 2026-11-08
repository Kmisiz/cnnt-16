echo "=== $(date -u) tu vps3 ==="
echo -n "vps3 -> vps2:8080 (phai CHAN, chi vps1 duoc goi): "; timeout 4 bash -c '</dev/tcp/10.10.10.20/8080' 2>/dev/null && echo "MO (LOI)" || echo "bi chan (tot)"
echo -n "vps3 -> vps2:22   (phai CHAN, chi vps4 duoc SSH) : "; timeout 4 bash -c '</dev/tcp/10.10.10.20/22' 2>/dev/null && echo "MO (LOI)" || echo "bi chan (tot)"
