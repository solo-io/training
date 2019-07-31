package main

import (
  "context"
  "log"
  "net"
  "strconv"

  "github.com/envoyproxy/go-control-plane/envoy/api/v2/core"
  pb "github.com/envoyproxy/go-control-plane/envoy/service/auth/v2"
  envoytype "github.com/envoyproxy/go-control-plane/envoy/type"
  googlerpc "github.com/gogo/googleapis/google/rpc"
  "github.com/gogo/protobuf/types"
  "google.golang.org/grpc"
  "google.golang.org/grpc/reflection"
)

const (
  port = ":8000"
)

type server struct {
}

func (s *server) Check(ctx context.Context, req *pb.CheckRequest) (*pb.CheckResponse, error) {
  http := req.GetAttributes().GetRequest().GetHttp()
  headers := http.GetHeaders()
  path := http.GetPath()

  log.Println(headers)
  log.Println(path)

  if path != "" {
    log.Println("Approved")
    return &pb.CheckResponse{
      Status: &googlerpc.Status{Code: int32(googlerpc.OK)},
      HttpResponse: &pb.CheckResponse_OkResponse{
        OkResponse: &pb.OkHttpResponse{
          Headers: []*core.HeaderValueOption{
            {
              Append: &types.BoolValue{Value: false},
              Header: &core.HeaderValue{
                Key:   "x-my-header",
                Value: "foo",
              },
            },
          },
        },
      },
    }, nil
  }

  log.Println("Denied")
  return &pb.CheckResponse{
    Status: &googlerpc.Status{Code: int32(googlerpc.PERMISSION_DENIED)},
    HttpResponse: &pb.CheckResponse_DeniedResponse{
      DeniedResponse: &pb.DeniedHttpResponse{
        Status: &envoytype.HttpStatus{Code: envoytype.StatusCode_Forbidden},
        Body:   "some denial message",
      },
    },
  }, nil
}

func main() {
  lis, err := net.Listen("tcp", port)
  if err != nil {
    log.Fatalf("failed to listen: %v", err)
  }

  s := grpc.NewServer()

  pb.RegisterAuthorizationServer(s, &server{})

  // Helps Gloo detect this is a gRPC service
  reflection.Register(s)

  if err := s.Serve(lis); err != nil {
    log.Fatalf("failed to serve: %v", err)
  }
}
