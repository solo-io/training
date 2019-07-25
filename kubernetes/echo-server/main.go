package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"time"

	"github.com/gorilla/mux"
)

type Route struct {
	Name        string
	Pattern     string
	HandlerFunc http.HandlerFunc
}
type Routes []Route

var routes = Routes{
	Route{
		"index", "/", index,
	},
	Route{
		"everything", "/{everything:.*}", everything,
	},
}

type RequestBody struct {
	String string
	// Other types?
}

// Request is the same as http.Request minus the bits that break json.Marshall
type Request struct {
	Method           string
	URL              *url.URL
	Proto            string // "HTTP/1.0"
	ProtoMajor       int    // 1
	ProtoMinor       int    // 0
	Header           http.Header
	Body             RequestBody
	ContentLength    int64
	TransferEncoding []string
	Host             string
	// Form url.Values
	// PostForm url.Values
	// MultipartForm *multipart.Form
	Trailer    http.Header
	RemoteAddr string
	RequestURI string
	// TLS *tls.ConnectionState
}

const megabytes = 1048576

func echo(w http.ResponseWriter, r *http.Request) {
	e := Request{}
	e.Method = r.Method
	e.URL = r.URL
	e.Proto = r.Proto
	e.ProtoMajor = r.ProtoMajor
	e.ProtoMinor = r.ProtoMinor
	e.Header = r.Header
	e.Body = RequestBody{}
	body, err := ioutil.ReadAll(io.LimitReader(r.Body, 1*megabytes))
	if err != nil {
		log.Fatal(err)
	}
	if err := r.Body.Close(); err != nil {
		log.Fatal(err)
	}
	e.Body.String = string(body)
	e.ContentLength = r.ContentLength
	e.TransferEncoding = r.TransferEncoding
	e.Host = r.Host
	e.Trailer = r.Trailer
	e.RemoteAddr = r.RemoteAddr
	e.RequestURI = r.RequestURI

	b, err := json.Marshal(e)
	if err != nil {
		log.Fatal(err)
	}
	_, _ = fmt.Fprint(w, string(b))
}

func index(w http.ResponseWriter, r *http.Request) {
	echo(w, r)
}

func everything(w http.ResponseWriter, r *http.Request) {
	echo(w, r)
}

func logger(inner http.Handler, name string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		inner.ServeHTTP(w, r)
		log.Printf(
			"%s\t%s\t%s\t%s",
			r.Method,
			r.RequestURI,
			name,
			time.Since(start),
		)
	})
}

func newRouter() *mux.Router {
	router := mux.NewRouter().StrictSlash(true)
	for _, route := range routes {
		var handler http.Handler
		handler = route.HandlerFunc
		handler = logger(handler, route.Name)
		router.
			Path(route.Pattern).
			Name(route.Name).
			Handler(handler)
	}
	return router
}

func main() {
	port := flag.Int("p", 8080, "Port")
	flag.Parse()

	router := newRouter()
	log.Println(fmt.Sprintf("Listening on port %v...", *port))
	log.Fatal(http.ListenAndServe(
		fmt.Sprintf(":%v", *port), router))
}
