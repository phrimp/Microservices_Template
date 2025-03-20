package main

import (
	"os"

	"github.com/gofiber/fiber/v2"
)

func main() {
	example_service := fiber.New()
	example_service.Get("/health", func(c *fiber.Ctx) error {
		return c.Status(fiber.StatusOK).JSON(fiber.Map{
			"status":  "ok",
			"service": "example-service",
		})
	})
	example_service.Listen(os.Getenv("SERVICE_PORT"))
}
