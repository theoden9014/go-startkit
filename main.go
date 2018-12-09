package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	listenAddr := ":8080"
	if addr := os.Getenv("ADDR"); len(addr) != 0 {
		listenAddr = addr
	}

	http.HandleFunc("/", func(wr http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(wr, "Hello World\n")
	})

	log.Fatal(http.ListenAndServe(listenAddr, nil))
}
