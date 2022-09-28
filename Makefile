build: bin
	go build -o bin/apiserver ./cmd/apiserver

bin:
	mkdir bin
