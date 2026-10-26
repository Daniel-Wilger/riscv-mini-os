# Symbole laden und verbinden
file build/mini_os.elf
target remote :1234

# Deine Breakpoints (entweder als Label oder Adresse)
break _start
break trap_handler
break syscall_handler
break scheduler

break user_a_code
break user_b_code

break sys_send
break send_done
break send_totaly_done

break sys_receive
break receive_done
break receive_totaly_done

break sys_exit

# Optional: Automatisch bis zum ersten Breakpoint laufen lassen
continue
